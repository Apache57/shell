# niri roadmap: from scaffold to a shell that runs on niri

> Target: Caelestia shell running on **niri** (latest), Hyprland kept dormant, **upstream merging
> clean**. Source of truth is upstream `caelestia-dots/shell`.
> Stage: **pre-alpha — scaffolding complete, no niri backend yet.** The shell does **not** run on
> niri today.
> **Last reviewed:** 2026-10-14 · **Last updated:** 2026-10-14.
> Effort bands are rough **estimates** (relative shirt-sizes, not measured hours or percentages).

## Where this stands

The governance scaffold, the compositor-seam design, the coupling audit, and the import/`hyprctl`
gate are in (PR #1). What does **not** exist yet is any runtime niri code: there is no
`services/Compositor.qml` and no `services/Niri.qml`, so nothing selects a niri backend and nothing
speaks niri's IPC. On a niri session today the shell would instantiate the *dormant* Hyprland backend
and come up with empty `workspaces`/`toplevels` and no-op `dispatch` — i.e. it does not work on niri.
This roadmap is the plan to change that. Every fact below is grounded in
[`docs/niri-architecture.md`](niri-architecture.md) (the seam) and
[`docs/niri-parity.md`](niri-parity.md) (the coupling surface + checklist); nothing here invents
behaviour those docs do not claim.

## Definition of done — what "it works on niri" means

"Works on niri" is not "the process launches." The bar, drawn from the real feature surface in
[`docs/niri-parity.md`](niri-parity.md):

| Done when | Source feature |
|---|---|
| Bar + workspaces render and **update live** on a niri session | `Compositor.workspaces` / `focusedWorkspace` from niri's `workspaces` + `WorkspacesChanged`/`WorkspaceActivated` |
| Active window + windowinfo show the focused toplevel | `Compositor.activeToplevel` from `focused-window` + `WindowFocusChanged` |
| Keyboard layout is shown (and switchable where niri allows) | `keyboard-layouts` + `KeyboardLayoutSwitched` |
| The shell **starts and stays up** across a niri session | `services/Compositor.qml` detects `$NIRI_SOCKET`, drives `services/Niri.qml` |
| The **Hyprland** session still works, unchanged | short-circuit backend select; `services/Hypr.qml` untouched |
| `scripts/niri/check-no-new-hyprland-coupling.sh` stays **green** and `sync-upstream.sh` reports **clean** | the gate + the prime directive |

Features with no niri analogue (special workspaces, runtime compositor-config writes, caps/num lock)
are **done when they degrade cleanly** — hidden or no-op and marked `⛔`/`🟡` in the parity doc —
never faked. See *Limitations*.

## Milestones

Bands: **S** small · **M** medium · **L** large — a rough planning estimate, not a measured figure.
"Covers" names the files/rows from [`docs/niri-parity.md`](niri-parity.md) each milestone closes.

| # | Goal | Covers | Effort (est.) | Status |
|---|---|---|---|---|
| **M0** | Scaffold, governance, coupling audit, import/`hyprctl` gate | `AGENTS.md`, `docs/niri-*`, `scripts/niri/*`, `.github/workflows/niri-no-new-hyprland-coupling.yml`, the 12-file baseline | — | ✅ done (PR #1) |
| **M1** | **The compositor seam** — the unblocker | `services/Compositor.qml` (new) + `services/Niri.qml` (new); runtime `$NIRI_SOCKET` detection; event-stream + `niri msg --json` queries + `niri msg action` dispatch | **L** | ⬜ next |
| **M2** | Workspaces in the bar | `modules/bar/components/workspaces/{Workspaces,Workspace}.qml`, `modules/bar/popouts/Wrapper.qml`, `modules/drawers/ContentWindow.qml`; `SpecialWorkspaces.qml` hidden | **M** | ⬜ |
| **M3** | Active window + windowinfo | `modules/windowinfo/{WindowInfo,Preview,Details}.qml` (some geometry/metadata fields may be absent — map honestly) | **M** | ⬜ |
| **M4** | Keybinds | `components/misc/CustomShortcut.qml`: ship a documented niri **KDL snippet** that calls the shell's IPC/CLI — the shell cannot register global shortcuts | **S–M** | ⬜ needs design |
| **M5** | Devices | keyboard layout via `keyboard-layouts` + `KeyboardLayoutSwitched` (`KbLayoutModel.qml`, `hyprdevices`); then caps/num lock, which niri IPC does **not** expose | **M** | ⬜ / 🟡 |
| **M6** | The long tail + runtime-config no-ops | `modules/areapicker/Picker.qml`, idle/lock, `hyprextras`; and the `Hypr.extras`-write features `services/GameMode.qml` + `services/Colours.qml` that become **no-ops** on niri; plus the ~dozen `Hypr.*` readers swapped to `Compositor` | **L** | ⬜ / ⛔ |
| **M7** | Companion dots fork | in `Apache57/caelestia` (separate repo): a `niri/` config beside `hypr/` — the KDL session, keybind snippet from M4, autostart | **M** | ⬜ |

Notes:

- **M1 is the gate on everything else.** Nothing in M2–M6 can be tested on niri until a backend
  exists and a consumer reads `Compositor` instead of `Hyprland`. Both new files are intentionally
  uncommitted in the scaffold because they must be written and run against a **live niri session**
  (QML can't be validated in this environment) — see *What is NOT in this scaffold yet* in
  [`docs/niri-architecture.md`](niri-architecture.md).
- **Migration is consumer-by-consumer.** Each migrated file drops its line from
  `scripts/niri/hyprland-consumers.baseline` in the same change, which shrinks the divergence count;
  nothing breaks mid-migration because an un-migrated file still runs on Hyprland unchanged.
- **M4/M7 are coupled:** the KDL snippet designed in M4 is what the dots fork ships in M7.

## Limitations / non-goals

Pulled straight from [`docs/niri-parity.md`](niri-parity.md) — stated, not softened:

- **No special/scratchpad workspaces.** niri has none; `SpecialWorkspaces.qml`,
  `toggleSpecial`/`cycleSpecialWorkspace` are hidden/no-op on niri. `⛔`
- **The shell cannot register global keybinds at runtime.** niri owns all keybinds in its KDL
  config. We ship a snippet; we do not bind shortcuts the Hyprland way. `⬜`
- **Caps/Num lock are absent from niri's IPC.** They need a separate source or are marked
  unavailable — never faked. `🟡`
- **Runtime Hyprland-config writes have no niri equivalent.** `GameMode`/`Colours` rewrite Hyprland
  settings live (animations, blur, gaps, layer rules); niri cannot be reconfigured over IPC, so these
  degrade to **no-ops**. `⛔`
- **Workspace identity differs.** Hyprland ids are global and persistent; niri's are per-output and
  dynamic — the bar must not assume stable global ids. `🟡`
- **Standing non-goal: never diverge from upstream more than necessary.** Prefer new files over edits;
  keep the diff small, additive, isolated. If a change would make the next `git merge upstream/main`
  conflict, it is the wrong change (see `AGENTS.md` §0).

## How progress is tracked

- **[`docs/niri-parity.md`](niri-parity.md)** — the per-feature checklist (`⬜`/`🟡`/`✅`/`⛔`); update
  the row with date + evidence when you close part of an item.
- **[`docs/niri-divergence.md`](niri-divergence.md)** — every edit to an upstream file and the current
  direct-importer count; regenerate with `scripts/niri/divergence.sh`. It should only shrink.
- **`log/devlog.md`** — the terse per-session log (what landed, which files, what's still open), per
  `AGENTS.md` §5. This is how the next session continues.
