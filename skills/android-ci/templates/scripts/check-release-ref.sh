#!/usr/bin/env bash
set -euo pipefail

sha="${1:?usage: check-release-ref.sh <sha> <tag> <version>}"
tag="${2:?usage: check-release-ref.sh <sha> <tag> <version>}"
version="${3:?usage: check-release-ref.sh <sha> <tag> <version>}"

if ! git ls-remote --exit-code --tags origin "refs/tags/$tag" > /dev/null; then
  echo "tag $tag does not exist on origin" >&2
  exit 1
fi
git fetch --quiet --force origin "+refs/heads/main:refs/remotes/origin/main" "refs/tags/$tag:refs/tags/$tag"

tagged="$(git rev-parse "refs/tags/$tag^{commit}")"
full="$(git rev-parse "$sha^{commit}")"
if [ "$tagged" != "$full" ]; then
  echo "tag $tag points at $tagged, not $full" >&2
  exit 1
fi

if ! git merge-base --is-ancestor "$full" origin/main; then
  echo "$full is not an ancestor of origin/main" >&2
  exit 1
fi

found="$(git show "$full:version.txt" | tr -d '[:space:]')"
if [ "$found" != "$version" ]; then
  echo "version.txt at $full is $found, expected $version" >&2
  exit 1
fi

echo "release ref ok: $tag at $full is $version"
