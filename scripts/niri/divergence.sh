#!/usr/bin/env bash
# Refresh the generated section of docs/niri-divergence.md: the current set of files that import
# Quickshell.Hyprland directly. This list should only shrink as consumers migrate to Compositor.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
doc="docs/niri-divergence.md"

# Match the SAME coupling the gate enforces: a direct Quickshell.Hyprland import OR a hyprctl
# shell-out. This keeps the generated count reconciled with the 12-file gate baseline.
pattern='(^[[:space:]]*import[[:space:]]+Quickshell\.Hyprland|\bhyprctl\b)'
coupled="$(grep -rlE "$pattern" --include='*.qml' . 2>/dev/null \
           | sed 's|^\./||' | sort -u)"
count="$(printf '%s\n' "$coupled" | grep -c . || true)"

block="$(
  printf '_Last refreshed: %s. Files coupled to Hyprland (import or hyprctl): %s (should only shrink)._\n\n' \
    "$(date -u +%Y-%m-%d)" "$count"
  printf '%s\n' "$coupled" | sed 's/^/- `/; s/$/`/'
)"

tmp="$(mktemp)"
awk -v block="$block" '
  /<!-- BEGIN generated -->/ { print; print block; skip=1; next }
  /<!-- END generated -->/   { skip=0 }
  !skip { print }
' "$doc" > "$tmp"
mv "$tmp" "$doc"
echo "updated $doc ($count direct importers)."
