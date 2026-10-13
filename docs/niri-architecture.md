# niri architecture: the compositor seam

Goal: run the Caelestia shell on niri without forking away from upstream. We do that by putting a
**single abstraction** between the shell and the compositor, then plugging a niri backend in behind
it. Upstream's Hyprland code stays exactly where it is.

## The three pieces

```
         consumers (bar, windowinfo, drawers, shortcuts, ...)
                              │  import qs.services; use Compositor.*
                              ▼
                   services/Compositor.qml          ← ours (the seam)
                    picks a backend at runtime
                   ┌──────────┴───────────┐
                   ▼                      ▼
        services/Hypr.qml         services/Niri.qml    ← ours
        (upstream, unchanged)     niri msg + event stream
                   │                      │
            Quickshell.Hyprland     $NIRI_SOCKET IPC
```

- **`services/Compositor.qml` (new, ours).** A `Singleton` that, at startup, detects the running
  compositor and exposes one stable interface, delegating every property and method to the active
  backend. Detection: `$NIRI_SOCKET` present → niri; else `$HYPRLAND_INSTANCE_SIGNATURE` present →
  Hyprland. Consumers only ever see `Compositor`. **Select the backend by short-circuit** (e.g.
  `readonly property QtObject active: isNiri ? Niri : Hypr`) so the dormant backend singleton is
  never referenced, hence never instantiated, on the active compositor. See the safety note below.
- **`services/Hypr.qml` (upstream, unchanged).** Already the Hyprland backend in all but name. We do
  **not** edit it; `Compositor` wraps it.
- **`services/Niri.qml` (new, ours).** Implements the same interface over niri's IPC: a long-lived
  process/socket on `niri msg --json event-stream` feeding reactive models, `niri msg --json`
  queries for initial state, and `niri msg action ...` for dispatch.

## Is wrapping Hyprland safe on niri? (yes, non-fatally)

Instantiating the Hyprland backend on a niri session does **not** crash or block the shell.
Quickshell's `Hyprland` singleton checks `$HYPRLAND_INSTANCE_SIGNATURE`; when it is unset it logs one
`qWarning` ("$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.") and returns — the
singleton exists but is inert (empty `workspaces`/`monitors`/`toplevels`, no-op `dispatch`). The
native `HyprExtras` plugin does the same (one `qCWarning`, early return). Source:
`quickshell/src/wayland/hyprland/ipc/connection.cpp` and `plugin/src/Caelestia/Services/hyprextras.cpp`.

So the "Compositor wraps both" design is sound and needs **no** `Loader` (a QML `Singleton` can't be
loaded anyway). The one real rule: QML singletons instantiate on first reference, so `Compositor`
must reach the dormant backend through a **short-circuited** selection and never otherwise, or it
pays those warnings for nothing. A caveat during migration: any consumer still importing
`Quickshell.Hyprland` / reading `Hypr.*` directly will instantiate `Hypr` on niri and emit those
harmless warnings (plus failed socket writes from `Hypr.qml`'s `reloadDynamicConfs()`), until it is
moved onto `Compositor`. Noise, not breakage.

## The interface both backends implement

Taken from what consumers already read off the Hypr service, so migration is mechanical:

| Member | Type | niri source |
|---|---|---|
| `toplevels` | model | `niri msg --json windows` + `WindowsChanged`/`WindowOpenedOrChanged`/`WindowClosed` |
| `workspaces` | model | `niri msg --json workspaces` + `WorkspacesChanged` |
| `monitors` | model | `niri msg --json outputs` |
| `focusedWorkspace` | obj | `WorkspaceActivated` / focused flag in `workspaces` |
| `focusedMonitor` | obj | focused output |
| `activeToplevel` | obj | `niri msg --json focused-window` + `WindowFocusChanged` |
| `activeWsId` | int | id of focused workspace |
| `dispatch(req)` | fn | map to `niri msg action <...>` |
| `focusWorkspace(ws)` | fn | `niri msg action focus-workspace <ref>` |
| `toggleSpecial(name)` | fn | **no-op on niri** (no special workspaces) |
| `capsLock` / `numLock` | bool | not in niri IPC — separate source or `false` (see parity doc) |
| `kbLayout` / `kbLayoutFull` | string | `niri msg --json keyboard-layouts` (`names` + `current_idx`) + `KeyboardLayoutSwitched` (active index) and `KeyboardLayoutsChanged` (configured set) |
| `configReloaded` | signal | emit on niri's `ConfigLoaded` event |

This table is the **state** surface. `Hypr` also exposes helpers and a config-write surface that a
backend must provide or `Compositor` must adapt: `usingLua`, `toplevelsForWs(ws, ignoredTags)`,
`isToplevelIgnored`, `trimWsName`, `monitorFor(screen)`, `monitorNames()`, `cycleSpecialWorkspace`,
`defaultKbLayout`, `lastSpecialWorkspace`, the `hypr` `IpcHandler`, and `extras`/`options`/`devices`
(`applyOptions`/`batchMessage`/`message`, used by `GameMode`/`Colours` to rewrite Hyprland config at
runtime — **no niri equivalent**; degrade to no-ops). The Lua-vs-text `dispatch` strings
(`Hypr.usingLua ? "hl.dsp.…" : "…"`) are Hyprland-only and must be mapped to `niri msg action …`.

## Migrating a consumer (the mechanical change, kept minimal)

Two kinds of consumer migrate. The 10 gate-tracked files **import `Quickshell.Hyprland`** (Hyprland
types/singleton); the dozen-odd others only **read the `Hypr` service** (`Hypr.*`) or shell out to
`hyprctl` (see `docs/niri-parity.md`). Both route through `Compositor`; only the first kind is in the
baseline. For each, when its feature is ready on niri:

1. Change `import Quickshell.Hyprland` → `import qs.services` and read from `Compositor` instead of
   `Hyprland` (for a `Hypr.*`-only consumer, just swap `Hypr` → `Compositor`; for a `hyprctl`
   consumer, replace the `Process` with a `Compositor` call). Keep the diff to the import line and the
   reference swap; change nothing else in the file.
2. Where the consumer used a Hyprland-only concept (special workspaces), guard it behind a
   `Compositor.hasSpecialWorkspaces` style flag so Hyprland keeps its behaviour and niri hides it.
3. Remove the file from `scripts/niri/hyprland-consumers.baseline`.

Doing it consumer-by-consumer keeps each PR small and each upstream merge cheap. Until a consumer is
migrated it keeps importing `Quickshell.Hyprland` and runs unchanged on Hyprland — nothing breaks
mid-migration.

## Why not just rip Hyprland out

Because the fork's reason to exist is receiving upstream updates. Deleting Hyprland code turns every
upstream change to those 10 files into a merge conflict. Wrapping instead of removing keeps our diff
to a handful of new files plus one-line swaps, which is what makes `sync-upstream.sh` boring — the
goal.

## What is NOT in this scaffold yet

`Compositor.qml` and `Niri.qml` are intentionally **not committed yet**: they need to be written and
tested against a live niri session (QML can't be validated in this environment). They are the first
implementation PR. This scaffold lands the rules, the map, and the gate so that PR has rails.
