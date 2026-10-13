# niri parity: coupling surface and feature checklist

> Target: Caelestia shell running on **niri** (latest), Hyprland kept dormant. Source of truth is
> upstream `caelestia-dots/shell`. Status: ⬜ missing · 🟡 partial · ✅ done · ⛔ n/a on niri.
> **Last reviewed:** 2026-10-14 (scaffold; no feature work landed yet).

## How niri exposes state (the replacement for `Quickshell.Hyprland`)

- **Query:** `niri msg --json <cmd>` — e.g. `workspaces`, `windows`, `outputs`, `focused-window`,
  `keyboard-layouts`.
- **Events:** the event stream on the socket at `$NIRI_SOCKET` (`niri msg --json event-stream`)
  pushes `WorkspacesChanged`, `WorkspaceActivated`, `WindowsChanged`, `WindowOpenedOrChanged`,
  `WindowClosed`, `WindowFocusChanged`, `KeyboardLayoutsChanged`, `KeyboardLayoutSwitched`, etc.
  The `Niri` service holds a long-lived process/socket on this and updates reactive models — the way
  `Quickshell.Hyprland` keeps its models live.
- **Dispatch:** actions go through `niri msg action <name> ...` (e.g. `focus-workspace`,
  `focus-column-left`), the analogue of Hyprland's `dispatch`.

## Coupling surface → niri plan

| Upstream file | Uses from Hyprland | niri plan | Status |
|---|---|---|---|
| `services/Hypr.qml` | whole model: toplevels, workspaces, monitors, focused*, dispatch, keyboard | **Mirror as `services/Niri.qml`** with identical interface; `services/Compositor.qml` selects it | ⬜ |
| `modules/bar/components/workspaces/Workspaces.qml` | `Hyprland.workspaces`, focused ws | consume `Compositor.workspaces`; niri workspaces are per-output, dynamic | ⬜ |
| `modules/bar/components/workspaces/Workspace.qml` | ws id/name, activate | `Compositor.focusWorkspace`; map id→niri workspace ref | ⬜ |
| `modules/bar/components/workspaces/SpecialWorkspaces.qml` | Hyprland special workspaces | niri has none | ⛔ hide on niri |
| `modules/bar/popouts/Wrapper.qml` | focused monitor/ws for popout placement | `Compositor.focusedMonitor` | ⬜ |
| `modules/drawers/ContentWindow.qml` | monitor/workspace context | `Compositor.focusedMonitor` | ⬜ |
| `modules/windowinfo/WindowInfo.qml` | active toplevel, title/class | `Compositor.activeToplevel` from `focused-window` | ⬜ |
| `modules/windowinfo/Preview.qml` | toplevel geometry for preview | niri window geometry from `windows`; some fields may be absent | 🟡 |
| `modules/windowinfo/Details.qml` | toplevel metadata | map available fields; mark gaps | 🟡 |
| `components/misc/CustomShortcut.qml` | **Hyprland global shortcuts** (keybinds) | niri owns keybinds in its KDL config; the shell cannot register global shortcuts the Hyprland way. Ship a documented niri keybind snippet that calls the shell's IPC / CLI | ⬜ needs design |
| `plugin/src/Caelestia/Services/hyprextras.{cpp,hpp}` | Hyprland options/extras (native) | niri equivalents where they exist; else neutral defaults so QML never sees null | ⬜ |
| `plugin/src/Caelestia/Services/hyprdevices.{cpp,hpp}` | keyboard devices: capsLock, numLock, active layout | niri `keyboard-layouts` + `KeyboardLayoutSwitched`; caps/num lock not in niri IPC — needs another source | 🟡 |

### Also compositor-coupled, but NOT caught by the import gate (no `Quickshell.Hyprland` import)

The gate only sees `import Quickshell.Hyprland`. These couple to Hyprland by shelling out to `hyprctl`
or by writing Hyprland config through `Hypr.extras`, and must be migrated onto `Compositor` by hand:

| Upstream file | Uses from Hyprland | niri plan | Status |
|---|---|---|---|
| `modules/bar/popouts/kblayout/KbLayoutModel.qml` | `hyprctl switchxkblayout` / `getoption input:kb_layout` / `devices` | no `hyprctl` on niri: query `keyboard-layouts`, switch via niri's layout action, track `KeyboardLayoutSwitched` | ⬜ |
| `modules/areapicker/Picker.qml` | `hyprctl cursorpos`; `Hypr.extras`, `Hypr.toplevelsForWs` | niri has no cursor-pos IPC — read the pointer from Qt/Wayland; windows from `niri msg --json windows` | 🟡 |
| `services/GameMode.qml` | `Hypr.extras.applyOptions`/`message` — rewrites Hyprland config (animations, blur, gaps…) at runtime | niri can't be reconfigured over IPC: no-op / mark unavailable on niri | ⛔ |
| `services/Colours.qml` | `Hypr.extras.batchMessage` — Hyprland `layerrule` blur/ignore_alpha | niri has no layer-rule IPC: no-op on niri | ⛔ |

Beyond these, every reader of the `Hypr` singleton (e.g. `modules/bar/Bar.qml`,
`modules/IdleMonitors.qml`, `modules/windowinfo/Buttons.qml`, `modules/bar/components/StatusIcons.qml`,
`modules/bar/components/status/LockStatus.qml`, `modules/lock/center/StateMessage.qml`,
`services/{NotifData,Notifs,ShellState}.qml`) must point at `Compositor` once the backend exists — a
`Hypr.` → `Compositor.` swap, not tracked by the gate.

## Known model mismatches (map honestly, never fake)

- **Special workspaces** — no niri equivalent. `SpecialWorkspaces.qml` and
  `Hypr.cycleSpecialWorkspace`/`toggleSpecial` become no-ops / hidden on niri. ⛔
- **Workspace identity** — Hyprland workspaces are globally numbered and persistent; niri's are
  per-output and dynamic. The bar must not assume stable global ids. 🟡
- **Global keybinds** — Hyprland registers shortcuts from the shell; niri owns all keybinds in its
  config. The fork ships a niri keybind snippet; it does not register shortcuts at runtime. ⬜
- **Caps/Num lock** — Hyprland surfaces these via the native plugin; niri's IPC does not, so this
  needs a separate source or is marked unavailable. 🟡
- **Runtime compositor config** — `GameMode`/`Colours` rewrite Hyprland settings live
  (`applyOptions`, `layerrule` blur). niri cannot be reconfigured over IPC, so these degrade to
  no-ops on niri. ⛔

## Work order (take the top open item)

1. `services/Niri.qml` + `services/Compositor.qml` with runtime backend detection. **Unblocks all.**
2. Workspaces in the bar (the most visible feature).
3. Active window + windowinfo.
4. Keybinds: ship and document the niri KDL snippet.
5. Devices: keyboard layout, then caps/num lock.
6. The long tail (idle, gamemode, area picker, lock) — audit each for a Hyprland assumption.
