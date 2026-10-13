#!/usr/bin/env bash
# Refresh the generated section of docs/niri-divergence.md: the current set of files that import
# Quickshell.Hyprland directly. This list should only shrink as consumers migrate to Compositor.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
doc="docs/niri-divergence.md"

importers="$(grep -rlE '^\s*import\s+Quickshell\.Hyprland' --include='*.qml' . 2>/dev/null \
             | sed 's|^\./||' | sort -u)"
count="$(printf '%s\n' "$importers" | grep -c . || true)"

block="$(
  printf '_Last refreshed: %s. Direct importers: %s (should only shrink)._\n\n' \
    "$(date -u +%Y-%m-%d)" "$count"
  printf '%s\n' "$importers" | sed 's/^/- `/; s/$/`/'
)"

tmp="$(mktemp)"
awk -v block="$block" '
  /<!-- BEGIN generated -->/ { print; print block; skip=1; next }
  /<!-- END generated -->/   { skip=0 }
  !skip { print }
' "$doc" > "$tmp"
mv "$tmp" "$doc"
echo "updated $doc ($count direct importers)."
