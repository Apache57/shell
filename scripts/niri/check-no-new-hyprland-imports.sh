#!/usr/bin/env bash
# Gate: no NEW direct `Quickshell.Hyprland` imports.
#
# Upstream reaches Hyprland through `import Quickshell.Hyprland` in a known set of files (the
# baseline). This fork routes all compositor access through `services/Compositor.qml` instead, so any
# file that imports Quickshell.Hyprland and is NOT in the baseline is a new direct coupling — it makes
# the fork harder to run on niri and harder to merge with upstream. Fail on those.
#
# Migrating a consumer onto Compositor? Remove its line from the baseline in the same change.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
baseline="scripts/niri/hyprland-consumers.baseline"

if [[ ! -f "$baseline" ]]; then
  echo "error: $baseline not found" >&2
  exit 2
fi

# Allowed paths (strip comments/blanks).
mapfile -t allowed < <(grep -vE '^\s*(#|$)' "$baseline" | sed 's/[[:space:]]*$//')

is_allowed() {
  local f="$1"
  for a in "${allowed[@]}"; do [[ "$f" == "$a" ]] && return 0; done
  return 1
}

violations=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if ! is_allowed "$f"; then violations+=("$f"); fi
done < <(grep -rlE '^\s*import\s+Quickshell\.Hyprland' --include='*.qml' . 2>/dev/null \
         | sed 's|^\./||' | sort -u)

# Also flag baseline entries that no longer import Hyprland (migrated but not removed from baseline),
# so the baseline can't rot. This is a warning, not a failure.
for a in "${allowed[@]}"; do
  if [[ -f "$a" ]] && ! grep -qE '^\s*import\s+Quickshell\.Hyprland' "$a"; then
    echo "note: $a is in the baseline but no longer imports Quickshell.Hyprland — remove it from $baseline" >&2
  fi
done

if (( ${#violations[@]} )); then
  echo "FAIL: new direct Quickshell.Hyprland import(s) — route these through services/Compositor.qml:" >&2
  printf '  %s\n' "${violations[@]}" >&2
  echo "If a file legitimately must stay a Hyprland backend, add it to $baseline with a comment." >&2
  exit 1
fi

echo "OK: no new direct Quickshell.Hyprland imports (${#allowed[@]} baseline files allowed)."
