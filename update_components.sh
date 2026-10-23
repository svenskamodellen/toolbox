#!/bin/zsh

# update_components.sh
#
# Updates every repo that depends on @svenskamodellen/components to the latest
# published version of that package.
#
# Usage:
#   ./update_components.sh
#
# Assumes the sibling-directory workspace layout documented in the toolbox
# readme (run from the toolbox repo; consumers live one level up).

set -e

cd "$(dirname "$0")/.."
workspace_root="$(pwd)"

pkg_name="@svenskamodellen/components"

for pkg_json in "${workspace_root}"/*/package.json; do
  dir="$(dirname "$pkg_json")"
  repo="$(basename "$dir")"

  # Skip the components package itself.
  if [ "$repo" = "svenskamodellen-components" ]; then
    continue
  fi

  # Only touch repos that actually depend on the package.
  if ! grep -q "\"$pkg_name\"" "$pkg_json"; then
    continue
  fi

  echo "Updating $pkg_name in $repo"
  # pnpm update --latest won't reliably bump a devDependency to a just-published
  # version, so resolve the latest explicitly and `pnpm add` it (keeping a caret
  # range). Use -D when the dep currently lives in devDependencies.
  latest=$(cd "$dir" && pnpm view "$pkg_name" dist-tags.latest 2>/dev/null)
  if [ -z "$latest" ]; then
    echo "warn: could not resolve latest version of $pkg_name for $repo" >&2
    continue
  fi

  add_flag=""
  if grep -A50 '"devDependencies"' "$pkg_json" | grep -q "\"$pkg_name\""; then
    add_flag="-D"
  fi

  # Don't let one repo's unrelated failure (e.g. ignored build scripts) abort
  # the whole run.
  if ! (cd "$dir" && pnpm add $add_flag "${pkg_name}@^${latest}"); then
    echo "warn: update in $repo exited non-zero (see output above)" >&2
  fi
done

echo "Done."
