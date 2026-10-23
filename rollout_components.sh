#!/bin/zsh

# rollout_components.sh
#
# Orchestrates a full rollout after @svenskamodellen/components has a new
# release. Chains the whole slog in the correct order:
#
#   1. Bump @svenskamodellen/components to latest in every consumer repo
#      (via update_components.sh).
#   2. For each autoindex repo (arbetsmiljo, kollektivavtal, lagstiftning):
#      commit the bump, create the next vN tag, and push commit + tags.
#   3. Run the existing bump_*_autoindex.sh scripts, which rewrite @vN refs
#      in the content/year repos to the new tag and commit+push them.
#   4. Commit + push the plain homepage repos (CI deploys them).
#   5. Build + deploy arbetsmiljo-homepage locally (one and done).
#
# Usage:
#   ./rollout_components.sh            # run the whole rollout
#   ./rollout_components.sh --dry-run  # show what would happen, change nothing
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
fi

pkg_name="@svenskamodellen/components"

# Autoindex repos and the bump script that propagates their new tag.
autoindex_repos=(
  arbetsmiljo-autoindex
  kollektivavtal-autoindex
  lagstiftning-autoindex
)

# Plain homepages that just commit + push (CI handles deploy).
plain_homepages=(
  kollektivavtal-homepage
  lagstiftning-homepage
  fackforbund-homepage
  svenskamodellen-homepage
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
# 1. Bump the package everywhere.
# ---------------------------------------------------------------------------
note "Step 1: bump ${pkg_name} to latest in all consumer repos"
if [ "$dry_run" -eq 1 ]; then
  echo "[dry-run] ${toolbox_dir}/update_components.sh"
else
  # update_components.sh already tolerates per-repo failures.
  "${toolbox_dir}/update_components.sh" || warnings+=("update_components.sh")
fi

# ---------------------------------------------------------------------------
# 2. Commit, tag (next vN), and push each autoindex repo.
# ---------------------------------------------------------------------------
note "Step 2: commit, tag, and push autoindex repos"
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
    echo "[dry-run] would commit bump, tag ${next_tag}, push commit + tags"
    cd "$workspace_root"
    continue
  fi

  if git diff --quiet; then
    echo "$repo: no package changes to commit; tagging current HEAD as ${next_tag}"
  else
    run "$repo: commit bump" git commit -am "Bump ${pkg_name} to latest" || true
  fi
  run "$repo: tag ${next_tag}" git tag "$next_tag" || true
  run "$repo: push commit" git push || true
  run "$repo: push tags" git push --tags || true

  cd "$workspace_root"
done

# ---------------------------------------------------------------------------
# 3. Propagate the new autoindex tags into the content/year repos.
# ---------------------------------------------------------------------------
note "Step 3: propagate new tags into content repos (bump_*_autoindex.sh)"
for script in bump_arbetsmiljo_autoindex.sh bump_kollektivavtal_autoindex.sh bump_lagstiftning_autoindex.sh; do
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
# 4. Commit + push the plain homepages.
# ---------------------------------------------------------------------------
note "Step 4: commit + push plain homepages"
for repo in "${plain_homepages[@]}"; do
  dir="${workspace_root}/${repo}"
  if [ ! -d "$dir" ]; then
    echo "skip: $repo (not found)"
    continue
  fi

  cd "$dir"
  if [ "$dry_run" -eq 1 ]; then
    echo "[dry-run] $repo: would commit bump and push"
    cd "$workspace_root"
    continue
  fi

  if git diff --quiet; then
    echo "$repo: no changes to commit"
  else
    run "$repo: commit bump" git commit -am "Bump ${pkg_name} to latest" || true
    run "$repo: push" git push || true
  fi
  cd "$workspace_root"
done

# ---------------------------------------------------------------------------
# 5. Build + deploy arbetsmiljo-homepage locally.
# ---------------------------------------------------------------------------
note "Step 5: build + deploy arbetsmiljo-homepage locally"
am_dir="${workspace_root}/arbetsmiljo-homepage"
if [ ! -d "$am_dir" ]; then
  echo "skip: arbetsmiljo-homepage (not found)"
elif [ "$dry_run" -eq 1 ]; then
  echo "[dry-run] arbetsmiljo-homepage: would commit bump, push, then pnpm ship"
else
  cd "$am_dir"
  if git diff --quiet; then
    echo "arbetsmiljo-homepage: no changes to commit"
  else
    run "arbetsmiljo-homepage: commit bump" git commit -am "Bump ${pkg_name} to latest" || true
    run "arbetsmiljo-homepage: push" git push || true
  fi
  run "arbetsmiljo-homepage: build + deploy (pnpm ship)" pnpm ship || true
  cd "$workspace_root"
fi

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
