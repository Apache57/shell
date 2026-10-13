# AGENTS.md: guide for AI agents and contributors

This repo is a **fork of [caelestia-dots/shell](https://github.com/caelestia-dots/shell)** whose one
job is to make the Caelestia shell run on **niri** (latest), with Hyprland kept intact but dormant,
**while merging every upstream update cleanly**. Read this file first, then `docs/niri-parity.md`.

The shell is Quickshell/QML + a native C++ plugin, GPL-3.0. Upstream owns all features; this fork
only *adds* a niri backend behind an abstraction and never diverges more than it must. If a change
here would make the next `git merge upstream/main` conflict, it is the wrong change.

## 0. The prime directive: stay mergeable with upstream

Everything below serves this. We receive Caelestia's updates forever, so our diff against upstream
must stay **small, additive, and isolated**.

- **Never delete or rewrite upstream files to "remove Hyprland."** Hyprland code stays. The
  compositor is chosen at runtime; on a niri session Hyprland simply goes dormant.
- **Prefer new files over edits to upstream files.** A niri backend is a new file. Touching an
  upstream file is a last resort, kept to the fewest lines, and justified in the PR.
- **Every edit to an upstream file must survive a merge.** Keep edits at natural seams (one import
  line, one binding); never reflow or reformat surrounding upstream code.
- **Sync upstream often** (`scripts/niri/sync-upstream.sh`) and keep our commits replayable on top.
- **Our additions are namespaced** so they never collide with an upstream path: niri docs under
  `docs/niri-*`, niri tooling under `scripts/niri/`, and our CI under
  `.github/workflows/niri-*.yml`.

## 1. Orientation

| Read | Why |
|---|---|
| `docs/niri-architecture.md` | The compositor seam: the `Compositor` interface and how backends plug in |
| `docs/niri-parity.md` | The exact Hyprland coupling surface + the niri feature checklist (done/partial/missing) |
| `docs/niri-divergence.md` | Every file we changed vs upstream, why, and its merge risk |
| `docs/niri-roadmap.md` | The staged plan to get there: milestones, definition of done, honest limits |
| upstream `README.md`, `shell.qml` | What the shell is and how it starts |

## 2. The coupling surface (what niri must replace)

Upstream reaches the compositor three ways: Quickshell's built-in `Quickshell.Hyprland` module, a
native C++ plugin, and a handful of direct `hyprctl` shell-outs. Verified against upstream:

**QML consumers of `Quickshell.Hyprland` (10 files):**
`services/Hypr.qml` (the central service) · `modules/drawers/ContentWindow.qml` ·
`modules/bar/components/workspaces/{Workspaces,Workspace,SpecialWorkspaces}.qml` ·
`modules/bar/popouts/Wrapper.qml` · `modules/windowinfo/{WindowInfo,Preview,Details}.qml` ·
`components/misc/CustomShortcut.qml` (global keybinds).

**Native C++ plugin:** `plugin/src/Caelestia/Services/hyprextras.{cpp,hpp}`,
`hyprdevices.{cpp,hpp}` (keyboard devices: capsLock/numLock/active layout, options). Reached from QML
as `Hypr.extras`/`Hypr.devices`, and also used to **write Hyprland config at runtime**
(`services/GameMode.qml`, `services/Colours.qml` via `applyOptions`/`batchMessage`) — niri has no
equivalent for that.

**Direct `hyprctl` shell-outs (2 files):**
`modules/bar/popouts/kblayout/KbLayoutModel.qml` (keyboard-layout query + `switchxkblayout`) and
`modules/areapicker/Picker.qml` (`hyprctl cursorpos`). They import no Hyprland module, but the gate
catches them too (it scans for `hyprctl`, not just imports). (`README.md`'s `hyprctl monitors` line is
a doc example, not shell code.)

The baseline (`scripts/niri/hyprland-consumers.baseline`) and the gate track both the **direct
`Quickshell.Hyprland` importers (10)** and the **`hyprctl` shell-outs (2)**. The one coupling the gate
can't cleanly catch is runtime config-writes via `Hypr.extras`/`Hypr.devices` (`services/GameMode.qml`,
`services/Colours.qml`) — those are tracked in `docs/niri-parity.md`, not the gate. niri exposes none
of this through Quickshell; its
integration is its own IPC: `niri msg --json` and the event-stream socket at `$NIRI_SOCKET`. The job
is to present that behind the same interface the consumers already use. Note: singletons in
`services/` are reached via the `qs.services` import path (there is no `qmldir` to edit).

## 3. Golden rules

1. **One compositor seam.** All compositor access goes through `services/Compositor.qml` (the
   singleton that picks a backend) and the backend files `services/Hypr.qml` (upstream, unchanged)
   and `services/Niri.qml` (ours). A **new** consumer must `import qs.services` and use `Compositor`,
   **never `import Quickshell.Hyprland` directly**, and never shell out to `hyprctl`. The gate
   (`scripts/niri/check-no-new-hyprland-coupling.sh`, CI
   `.github/workflows/niri-no-new-hyprland-coupling.yml`) fails on any direct `Quickshell.Hyprland`
   import or `hyprctl` call in a file not listed in `scripts/niri/hyprland-consumers.baseline`.
2. **Same interface, both backends.** `Niri.qml` exposes the exact properties and methods consumers
   use on the Hypr service: `toplevels`, `workspaces`, `monitors`, `focusedWorkspace`,
   `focusedMonitor`, `activeToplevel`, `activeWsId`, `dispatch(req)`, `focusWorkspace(ws)`,
   `toggleSpecial(name)`, keyboard state (`capsLock`, `numLock`, `kbLayout`), and the
   `configReloaded` signal. Mismatched shapes break consumers silently — match them, or adapt in
   `Compositor`.
3. **Backend detection is runtime, not build-time.** niri when `$NIRI_SOCKET` is set, Hyprland when
   `$HYPRLAND_INSTANCE_SIGNATURE` is set. One build runs on both; never `#ifdef` a compositor out.
   "Disable Hyprland" = it is not selected, not that it is deleted.
4. **niri has no special workspaces.** niri uses scrollable columns on dynamic, per-output
   workspaces. It *does* have named workspaces, but no *special* (scratchpad) workspaces like
   Hyprland's. Features with no niri equivalent degrade
   gracefully (hidden or no-op) and are marked `n/a (niri)` in `docs/niri-parity.md` — never faked.
5. **Never break the Hyprland session.** A niri change must leave Hyprland working. If you can't test
   both, say so in the PR so a reviewer on the other compositor checks.
6. **Match upstream style.** `.clang-format`, `.editorconfig`, the QML conventions upstream uses. Our
   files look like their files.

## 4. Picking work

1. Read `docs/niri-parity.md`; take the highest `missing`/`partial` item nobody is on. Order:
   the `Niri` service + `Compositor` → workspaces (the bar) → active window / windowinfo → keybinds
   (`CustomShortcut`) → devices (keyboard layout/locks) → the long tail (idle, gamemode, lock, area
   picker).
2. When you close part of an item, update its row in `docs/niri-parity.md` with the date and
   evidence, and update `docs/niri-divergence.md` if you touched an upstream file. When you migrate a
   consumer onto `Compositor`, remove it from `scripts/niri/hyprland-consumers.baseline`.

## 5. Before you finish a task

```sh
scripts/niri/check-no-new-hyprland-coupling.sh   # new consumers use Compositor, not Hyprland
scripts/niri/divergence.sh                        # regenerate docs/niri-divergence.md; keep the diff small
# the shell must still build and start on BOTH compositors (build per upstream README / flake.nix)
# merge-safety check against upstream:
git fetch upstream && git merge-tree "$(git merge-base HEAD upstream/main)" HEAD upstream/main \
  | grep -q '^<<<<<<<' && echo "WARN: would conflict with upstream" || echo "merges clean"
```

Then append a terse entry to `log/devlog.md` (what landed, which files, what's still open). Sessions
end abruptly; the devlog plus a buildable tree is how the next agent continues.

## 6. Syncing upstream (the whole point)

`scripts/niri/sync-upstream.sh` adds/refreshes the `upstream` remote
(`https://github.com/caelestia-dots/shell`), fetches, and reports whether we merge clean. Run it
often. If upstream reworks a file we edited, resolve by re-applying our *minimal* change to the new
upstream version — never by keeping our whole old file. The smaller our diff, the cheaper every
future merge; shrinking divergence is always welcome work. Never push to `upstream`; open a PR there
only for changes that are genuinely compositor-agnostic and useful to everyone.
