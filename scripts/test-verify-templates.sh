#!/usr/bin/env bash
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/verify-templates.sh"
reference="$root/skills/android-ci/reference/libs.versions.toml"
work=$(mktemp -d "${TMPDIR:-/tmp}/verify-templates-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT

fail() {
  echo "assertion failed: $*" >&2
  exit 1
}

consumer() {
  local dir="$work/$1" file
  mkdir -p "$dir"
  while IFS= read -r -d '' file; do
    mkdir -p "$dir/$(dirname "${file#skills/*/templates/}")"
    cp "$root/$file" "$dir/${file#skills/*/templates/}"
  done < <(git -C "$root" ls-files -z -- skills/git-hooks/templates skills/android-ci/templates)
  printf '%s' "$dir"
}

run() {
  rc=0
  "$script" "$1" >"$work/out" 2>&1 || rc=$?
}

matchingCatalogHasNoDrift() {
  local dir
  dir=$(consumer match)
  mkdir -p "$dir/gradle"
  cp "$reference" "$dir/gradle/libs.versions.toml"
  run "$dir"
  [ "$rc" -eq 0 ] || fail "exit $rc: $(cat "$work/out")"
  grep -qx '0 drift' "$work/out" || fail "no 0 drift: $(cat "$work/out")"
  grep -q 'catalog versions checked' "$work/out" || fail "catalog not checked: $(cat "$work/out")"
}

differentVersionIsDrift() {
  local dir
  dir=$(consumer differ)
  mkdir -p "$dir/gradle"
  sed 's/^agp = ".*"/agp = "0.0.1"/' "$reference" >"$dir/gradle/libs.versions.toml"
  run "$dir"
  [ "$rc" -eq 1 ] || fail "exit $rc, wanted 1: $(cat "$work/out")"
  grep -q '^drift: gradle/libs.versions.toml version agp is 0.0.1' "$work/out" || fail "no agp drift line: $(cat "$work/out")"
  grep -qx '1 drift' "$work/out" || fail "no 1 drift: $(cat "$work/out")"
}

keysOnOneSideAreIgnored() {
  local dir
  dir=$(consumer extra)
  mkdir -p "$dir/gradle"
  {
    printf '[versions]\nprojectOnly = "1.0"\n'
    grep -v '^agp = ' "$reference" | sed '1d'
  } >"$dir/gradle/libs.versions.toml"
  run "$dir"
  [ "$rc" -eq 0 ] || fail "exit $rc: $(cat "$work/out")"
  grep -qx '0 drift' "$work/out" || fail "no 0 drift: $(cat "$work/out")"
}

librariesSectionIsNotCompared() {
  local dir
  dir=$(consumer libs)
  mkdir -p "$dir/gradle"
  {
    cat "$reference"
    printf '\n[plugins]\nagp = "0.0.1"\n'
  } >"$dir/gradle/libs.versions.toml"
  run "$dir"
  [ "$rc" -eq 0 ] || fail "exit $rc: $(cat "$work/out")"
}

missingCatalogIsNotChecked() {
  local dir
  dir=$(consumer none)
  run "$dir"
  [ "$rc" -eq 0 ] || fail "exit $rc: $(cat "$work/out")"
  grep -q 'no gradle/libs.versions.toml' "$work/out" || fail "no note: $(cat "$work/out")"
}

tests=(
  matchingCatalogHasNoDrift
  differentVersionIsDrift
  keysOnOneSideAreIgnored
  librariesSectionIsNotCompared
  missingCatalogIsNotChecked
)

passed=0
failed=0
for name in "${tests[@]}"; do
  if (set -e; "$name"); then
    echo "PASS $name"
    passed=$((passed + 1))
  else
    echo "FAIL $name"
    failed=$((failed + 1))
  fi
done

echo "$passed passed"
if [ "$failed" -ne 0 ]; then
  echo "$failed failed" >&2
  exit 1
fi
