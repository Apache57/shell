# Divergence from upstream

This fork's reason to exist is receiving `caelestia-dots/shell` updates forever, so this file tracks
**every way we differ from upstream** and the merge risk of each. Keep it short; a growing list here
is a warning sign. Regenerate the generated section with `scripts/niri/divergence.sh`.

## Principle

- New files (ours): **zero** merge risk — upstream never touches these paths. Namespaced as
  `docs/niri-*`, `scripts/niri/`, `.github/workflows/niri-*.yml`, and the niri backend/seam
  (`services/Niri.qml`, `services/Compositor.qml`).
- Edits to upstream files: **real** merge risk. Each one is listed below with why it was unavoidable
  and how small it is. The goal is to keep this table empty or nearly so.

## Edits to upstream files

| Upstream file | Lines changed | Why unavoidable | Merge risk |
|---|---:|---|---|
| _(none yet)_ | 0 | scaffold adds only new files | none |

## New files (ours)

| Path | Purpose |
|---|---|
| `AGENTS.md` | fork governance (overwrites upstream's if present — reconcile on merge) |
| `docs/niri-architecture.md` | the compositor seam design |
| `docs/niri-parity.md` | coupling surface + feature checklist |
| `docs/niri-divergence.md` | this file |
| `scripts/niri/*` | sync, gate, divergence tooling + the consumers baseline |
| `.github/workflows/niri-no-new-hyprland-coupling.yml` | the coupling gate in CI |

> Note: `AGENTS.md` is the one new file whose name *could* also exist upstream. If upstream adds its
> own `AGENTS.md`, merge the two by hand rather than clobbering either.

## Generated: current direct `Quickshell.Hyprland` importers

Run `scripts/niri/divergence.sh` to refresh. These should only ever shrink (as consumers migrate to
`Compositor`), never grow.

<!-- BEGIN generated -->
_Last refreshed: 2026-10-13. Direct importers: 10 (should only shrink)._

- `components/misc/CustomShortcut.qml`
- `modules/bar/components/workspaces/SpecialWorkspaces.qml`
- `modules/bar/components/workspaces/Workspace.qml`
- `modules/bar/components/workspaces/Workspaces.qml`
- `modules/bar/popouts/Wrapper.qml`
- `modules/drawers/ContentWindow.qml`
- `modules/windowinfo/Details.qml`
- `modules/windowinfo/Preview.qml`
- `modules/windowinfo/WindowInfo.qml`
- `services/Hypr.qml`
<!-- END generated -->
