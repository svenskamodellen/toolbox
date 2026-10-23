#!/bin/zsh

# link_components.sh
#
# Links the local ./svenskamodellen-components package into every -homepage
# and -autoindex repo so changes to the component library (CSS + TS) can be
# tested without publishing to the registry.
#
# Usage:
#   ./link_components.sh          # link the local source into all consumers
#   ./link_components.sh --unlink # restore the published registry version
#
# Assumes the sibling-directory workspace layout documented in the toolbox
# readme (run from the toolbox repo; consumers live one level up).

set -e

cd "$(dirname "$0")/.."
workspace_root="$(pwd)"

components_dir="${workspace_root}/svenskamodellen-components"
pkg_name="@svenskamodellen/components"

consumers=(
  arbetsmiljo-autoindex
  arbetsmiljo-homepage
  fackforbund-homepage
  kollektivavtal-autoindex
  kollektivavtal-homepage
  lagstiftning-autoindex
  lagstiftning-homepage
  svenskamodellen-homepage
)

mode="link"
if [ "$1" = "--unlink" ]; then
  mode="unlink"
fi

if [ ! -d "$components_dir" ]; then
  echo "error: components package not found at $components_dir" >&2
  exit 1
fi

for repo in "${consumers[@]}"; do
  dir="${workspace_root}/${repo}"
  if [ ! -d "$dir" ]; then
    echo "skip: $repo (not found)"
    continue
  fi

  if [ "$mode" = "link" ]; then
    echo "Linking $pkg_name into $repo"
    (cd "$dir" && pnpm link "$components_dir")
  else
    echo "Unlinking $pkg_name from $repo (reinstalling published version)"
    (cd "$dir" && pnpm unlink "$pkg_name" && pnpm install)
  fi
done

echo "Done."
