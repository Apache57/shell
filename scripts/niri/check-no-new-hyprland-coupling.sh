#!/usr/bin/env bash
# Gate: no NEW direct Hyprland coupling.
#
# Upstream reaches Hyprland two ways a static check can catch: `import Quickshell.Hyprland` and a
# `hyprctl` shell-out. Both are listed in the baseline. Any OTHER file that does either is a new
# direct coupling — it makes the fork harder to run on niri and harder to merge with upstream. Fail
# on those, and route them through `services/Compositor.qml` instead.
#
# (A third coupling — writing Hyprland config at runtime via `Hypr.extras`/`Hypr.devices` — is a
# property access this static gate can't cleanly distinguish from ordinary service reads, so it is
# tracked in docs/niri-parity.md, not here.)
#
# Migrating a file onto Compositor? Remove its line from the baseline in the same change.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
baseline="scripts/niri/hyprland-consumers.baseline"
# Matches a direct Quickshell.Hyprland import OR a hyprctl invocation.
pattern='(^[[:space:]]*import[[:space:]]+Quickshell\.Hyprland|\bhyprctl\b)'

if [[ ! -f "$baseline" ]]; then
  echo "error: $baseline not found" >&2
  exit 2
fi

# Allowed paths (strip comments/blanks/trailing space).
mapfile -t allowed < <(grep -vE '^[[:space:]]*(#|$)' "$baseline" | sed 's/[[:space:]]*$//')

is_allowed() {
  local f="$1" a
  for a in "${allowed[@]:-}"; do [[ "$f" == "$a" ]] && return 0; done
  return 1
}

# Every .qml that couples to Hyprland (import or hyprctl), repo-relative, deduped.
coupled=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  coupled+=("$f")
done < <(grep -rlE "$pattern" --include='*.qml' . 2>/dev/null | sed 's|^\./||' | sort -u)

violations=()
for f in "${coupled[@]:-}"; do
  [[ -z "$f" ]] && continue
  is_allowed "$f" || violations+=("$f")
done

# Rot check: baseline files that no longer couple to Hyprland at all (migrated but not removed).
for a in "${allowed[@]:-}"; do
  [[ -z "$a" || ! -f "$a" ]] && continue
  if ! grep -qE "$pattern" "$a"; then
    echo "note: $a is in the baseline but no longer couples to Hyprland — remove it from $baseline" >&2
  fi
done

if (( ${#violations[@]} )); then
  echo "FAIL: new direct Hyprland coupling (Quickshell.Hyprland import or hyprctl) — route these through services/Compositor.qml:" >&2
  printf '  %s\n' "${violations[@]}" >&2
  echo "If a file legitimately must stay a Hyprland backend, add it to $baseline with a comment." >&2
  exit 1
fi

echo "OK: no new direct Hyprland coupling (${#allowed[@]} baseline files allowed)."
