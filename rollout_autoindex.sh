#!/bin/zsh

# rollout_autoindex.sh
#
# Rolls out changes that live *inside* the autoindex repos themselves (e.g. a
# tweak to a shared component, a `lang` attribute change, a template fix) out
# to the content/year repos that pin those autoindexes by tag.
#
# Unlike rollout_components.sh, this does NOT bump @svenskamodellen/components.
# It assumes you've already made + staged/unstaged your edits in the autoindex
# repos, and just need to commit, tag the next vN, push, and propagate the new
# tag into the content/year repos.
#
# For each autoindex repo (arbetsmiljo, kollektivavtal, lagstiftning):
#   1. Commit any uncommitted changes.
#   2. Compute + create the next vN tag.
#   3. Push the commit and tags.
# Then run the existing bump_*_autoindex.sh scripts, which rewrite @vN refs in
# the content/year repos to the new tag and commit+push them.
#
# Usage:
#   ./rollout_autoindex.sh "<commit message>"            # run the rollout
#   ./rollout_autoindex.sh                               # default commit message
#   ./rollout_autoindex.sh --dry-run ["<commit message>"] # show, change nothing
#
# Assumes the sibling-directory workspace layout documented in the toolbox
# readme (run from the toolbox repo; consumers live one level up).

set -e

cd "$(dirname "$0")/.."
workspace_root="$(pwd)"
toolbox_dir="${workspace_root}/svenskamodellen-toolbox"

dry_run=0
if [ "$1" = "--dry-run" ]; then
  dry_run=1
  shift
fi

commit_message="${1:-Roll out autoindex changes}"

# Autoindex repos and the bump script that propagates their new tag.
autoindex_repos=(
  arbetsmiljo-autoindex
  kollektivavtal-autoindex
  lagstiftning-autoindex
)

bump_scripts=(
  bump_arbetsmiljo_autoindex.sh
  bump_kollektivavtal_autoindex.sh
  bump_lagstiftning_autoindex.sh
)

warnings=()

note() { echo "\n==> $1"; }

run() {
  # run "<description>" <command...>
  local desc="$1"; shift
  if [ "$dry_run" -eq 1 ]; then
    echo "[dry-run] $desc"
    echo "          $*"
    return 0
  fi
  echo "-> $desc"
  if ! "$@"; then
    warnings+=("$desc")
    echo "warn: step failed: $desc" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 1. Commit, tag (next vN), and push each autoindex repo.
# ---------------------------------------------------------------------------
note "Step 1: commit, tag, and push autoindex repos"
echo "Commit message: ${commit_message}"
for repo in "${autoindex_repos[@]}"; do
  dir="${workspace_root}/${repo}"
  if [ ! -d "$dir" ]; then
    echo "skip: $repo (not found)"
    continue
  fi

  cd "$dir"

  highest=$(git tag -l | grep -E '^v[0-9]+$' | sort -V | tail -n 1)
  next_num=$(( ${highest#v} + 1 ))
  next_tag="v${next_num}"
  echo "$repo: highest tag ${highest:-<none>} -> new tag ${next_tag}"

  if [ "$dry_run" -eq 1 ]; then
    echo "[dry-run] would commit changes, tag ${next_tag}, push commit + tags"
    cd "$workspace_root"
    continue
  fi

  if git diff --quiet && git diff --cached --quiet; then
    echo "$repo: no changes to commit; tagging current HEAD as ${next_tag}"
  else
    run "$repo: commit changes" git commit -am "$commit_message" || true
  fi
  run "$repo: tag ${next_tag}" git tag "$next_tag" || true
  run "$repo: push commit" git push || true
  run "$repo: push tags" git push --tags || true

  cd "$workspace_root"
done

# ---------------------------------------------------------------------------
# 2. Propagate the new autoindex tags into the content/year repos.
# ---------------------------------------------------------------------------
note "Step 2: propagate new tags into content repos (bump_*_autoindex.sh)"
for script in "${bump_scripts[@]}"; do
  if [ "$dry_run" -eq 1 ]; then
    echo "[dry-run] ${toolbox_dir}/${script}"
    continue
  fi
  echo "-> running ${script}"
  if ! (cd "$toolbox_dir" && "./${script}"); then
    warnings+=("$script")
    echo "warn: ${script} exited non-zero" >&2
  fi
done

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------
note "Rollout complete"
if [ ${#warnings[@]} -eq 0 ]; then
  echo "All steps succeeded."
else
  echo "Finished with ${#warnings[@]} warning(s):"
  for w in "${warnings[@]}"; do
    echo "  - $w"
  done
  exit 1
fi
