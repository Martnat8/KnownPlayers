#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [[ $# == 1 && $1 == --staged ]]; then
  if ! git cat-file -e :CHANGELOG.md 2>/dev/null || git diff --cached --quiet -- CHANGELOG.md; then
    echo 'Every commit must update CHANGELOG.md. Add a descriptive bullet under [Unreleased] and stage the file.' >&2
    exit 1
  fi
elif [[ $# == 3 && $1 == --range ]]; then
  base=$2
  head=$3
  git rev-parse --verify "${head}^{commit}" >/dev/null
  if [[ $base =~ ^0+$ ]]; then
    commits=$(git rev-list "$head")
  else
    git rev-parse --verify "${base}^{commit}" >/dev/null
    commits=$(git rev-list "$base..$head")
  fi
  failed=0
  for commit in $commits; do
    parent=$(git rev-parse --verify -q "$commit^1" || git hash-object -t tree /dev/null)
    if ! git cat-file -e "$commit:CHANGELOG.md" 2>/dev/null || git diff --quiet "$parent" "$commit" -- CHANGELOG.md; then
      echo "Commit $commit must update CHANGELOG.md (each commit, not just the final PR diff)." >&2
      failed=1
    fi
  done
  exit "$failed"
else
  echo 'Usage: scripts/check-changelog.sh --staged | --range BASE HEAD' >&2
  exit 1
fi
