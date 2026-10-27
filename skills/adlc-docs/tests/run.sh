#!/usr/bin/env bash
set -u

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPTS_DIR=$(cd "$TESTS_DIR/../scripts" && pwd)
FIXTURES_DIR="$TESTS_DIR/fixtures"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/adlc-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
export TESTS_DIR SCRIPTS_DIR FIXTURES_DIR TMP_ROOT

. "$TESTS_DIR/lib/assert.sh"
for file in "$TESTS_DIR"/test_*.sh; do
  . "$file"
done

failed=0
total=0
for fn in $(declare -F | awk '$3 ~ /^t_/ {print $3}' | sort); do
  total=$((total + 1))
  T="$TMP_ROOT/$fn"
  mkdir -p "$T"
  export T
  if out=$( (set -e; "$fn") 2>&1); then
    printf 'ok %s\n' "$fn"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$fn"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
done

printf '%s tests, %s failed\n' "$total" "$failed"
[ "$failed" -eq 0 ]
