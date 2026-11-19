#!/usr/bin/env bash
set -euo pipefail

tag="${1:?usage: publish-release.sh <tag> <apk> <checksum-file>}"
apk="${2:?usage: publish-release.sh <tag> <apk> <checksum-file>}"
checksum="${3:?usage: publish-release.sh <tag> <apk> <checksum-file>}"

is_draft="$(gh release view "$tag" --json isDraft --jq .isDraft)"
if [ "$is_draft" = "false" ]; then
  echo "already published"
  exit 0
fi

gh release upload "$tag" "$apk" "$checksum" --clobber
gh release edit "$tag" --draft=false
