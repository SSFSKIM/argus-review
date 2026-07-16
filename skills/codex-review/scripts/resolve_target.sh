#!/usr/bin/env bash
# Port of merge_base_with_head (codex-rs/git-utils/src/branch.rs).
# Prints the merge-base SHA between HEAD and <base-branch>, preferring the
# branch's upstream when that upstream exists and is ahead of the local branch.
# Exits non-zero when HEAD or the branch cannot be resolved (caller should then
# fall back to the reviewer's self-resolution instructions).
set -euo pipefail

branch="${1:?usage: resolve_target.sh <base-branch>}"

git rev-parse --verify --quiet HEAD >/dev/null || { echo "error: repository has no HEAD" >&2; exit 1; }
git rev-parse --verify --quiet "$branch" >/dev/null || { echo "error: cannot resolve branch: $branch" >&2; exit 1; }

ref="$branch"
if upstream="$(git rev-parse --abbrev-ref --verify --quiet "$branch@{upstream}" 2>/dev/null)"; then
    # Prefer the upstream only when it is ahead of the local branch.
    if [ "$(git rev-list --count "$branch..$upstream")" -gt 0 ]; then
        ref="$upstream"
    fi
fi

git merge-base HEAD "$ref"
