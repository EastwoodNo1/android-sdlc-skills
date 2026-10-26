#!/usr/bin/env bash
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "usage: $0 <consumer-repo-path>" >&2
  exit 2
fi
consumer=$(cd "$1" && pwd) || exit 2
root=$(cd "$(dirname "$0")/.." && pwd) || exit 2
drift=0
total=0
list=$(mktemp) || exit 2
trap 'rm -f "$list"' EXIT
git -C "$root" ls-files -z -- skills/git-hooks/templates skills/android-ci/templates >"$list" || exit 2
while IFS= read -r -d '' file; do
  rel=${file#skills/*/templates/}
  total=$((total + 1))
  if [ ! -f "$consumer/$rel" ]; then
    echo "drift: $rel is missing in $consumer"
    drift=$((drift + 1))
  elif ! cmp -s "$root/$file" "$consumer/$rel"; then
    echo "drift: $rel differs from $file"
    drift=$((drift + 1))
  fi
done <"$list"
echo "$total templates checked"
echo "$drift drift"
[ "$drift" -eq 0 ]
