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

toml_versions() {
  awk '
    /^[[:space:]]*\[/ { in_versions = ($0 ~ /^[[:space:]]*\[versions\][[:space:]]*$/); next }
    in_versions && /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=[[:space:]]*"[^"]*"/ {
      key = $0; sub(/^[[:space:]]*/, "", key); sub(/[[:space:]]*=.*/, "", key)
      value = $0; sub(/^[^"]*"/, "", value); sub(/".*/, "", value)
      print key "\t" value
    }
  ' "$1"
}

reference=skills/android-ci/reference/libs.versions.toml
catalog=gradle/libs.versions.toml
if [ -f "$consumer/$catalog" ]; then
  checked=0
  while IFS="$(printf '\t')" read -r key want; do
    have=$(toml_versions "$consumer/$catalog" | awk -F '\t' -v k="$key" '$1 == k { print $2; exit }')
    [ -n "$have" ] || continue
    checked=$((checked + 1))
    if [ "$have" != "$want" ]; then
      echo "drift: $catalog version $key is $have in the project, $want in $reference"
      drift=$((drift + 1))
    fi
  done < <(toml_versions "$root/$reference")
  echo "$checked catalog versions checked"
else
  echo "no $catalog in $consumer, catalog versions not checked"
fi
echo "$drift drift"
[ "$drift" -eq 0 ]
