#!/usr/bin/env bash
# Sync with Caelestia upstream — the whole reason this fork is structured the way it is.
# Adds/refreshes the `upstream` remote, fetches it, and reports whether we merge clean.
# It does NOT auto-merge by default (pass --merge to merge upstream/<branch> into HEAD).
set -euo pipefail

UPSTREAM_URL="https://github.com/caelestia-dots/shell"
branch="${1:-main}"
do_merge=0
[[ "${1:-}" == "--merge" ]] && { do_merge=1; branch="${2:-main}"; }

cd "$(git rev-parse --show-toplevel)"

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
  echo "added upstream -> $UPSTREAM_URL"
fi

git fetch upstream "$branch"

base="$(git merge-base HEAD "upstream/$branch")"
if git merge-tree "$base" HEAD "upstream/$branch" | grep -qE '^<<<<<<<'; then
  echo "CONFLICT: merging upstream/$branch would conflict. Resolve by re-applying our MINIMAL change"
  echo "to the new upstream file — never keep our whole old file. See docs/niri-divergence.md."
  status=1
else
  echo "CLEAN: upstream/$branch merges without conflict."
  status=0
fi

echo "--- commits on upstream/$branch not in HEAD ---"
git log --oneline "HEAD..upstream/$branch" | head -40

if (( do_merge )); then
  echo "--- merging upstream/$branch ---"
  git merge --no-edit "upstream/$branch"
fi

exit $status
