#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/check-ui-test-results.sh"
work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ui-guard-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "assertion failed: $*" >&2
  exit 1
}

suite() {
  local name="$1" attrs="$2"
  mkdir -p "$work/$name"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="s" %s>\n</testsuite>\n' "$attrs" > "$work/$name/TEST-s.xml"
}

expect_pass() {
  "$guard" "$work/$1" > /dev/null 2>&1 || fail "$1: guard rejected a good result"
}

expect_reject() {
  if "$guard" "$work/$1" > /dev/null 2>&1; then
    fail "$1: guard accepted a bad result"
  fi
}

passesWhenSomeTestsRan() {
  suite some 'tests="5" skipped="1" failures="0" errors="0"'
  expect_pass some
}

passesWhenNothingSkipped() {
  suite none 'tests="3" skipped="0" failures="0" errors="0"'
  expect_pass none
}

rejectsWhenEveryTestWasSkipped() {
  suite allskipped 'tests="4" skipped="4" failures="0" errors="0"'
  expect_reject allskipped
}

rejectsWhenSkippedExceedsTests() {
  suite oversk 'tests="2" skipped="3" failures="0" errors="0"'
  expect_reject oversk
}

rejectsWhenNoTestsRan() {
  suite zero 'tests="0" skipped="0" failures="0" errors="0"'
  expect_reject zero
}

rejectsAFailure() {
  suite failing 'tests="3" skipped="0" failures="1" errors="0"'
  expect_reject failing
}

rejectsAnError() {
  suite erroring 'tests="3" skipped="0" failures="0" errors="1"'
  expect_reject erroring
}

rejectsAnEmptyDirectory() {
  mkdir -p "$work/empty"
  expect_reject empty
}

tests=(
  passesWhenSomeTestsRan
  passesWhenNothingSkipped
  rejectsWhenEveryTestWasSkipped
  rejectsWhenSkippedExceedsTests
  rejectsWhenNoTestsRan
  rejectsAFailure
  rejectsAnError
  rejectsAnEmptyDirectory
)

passed=0
failed=0
for name in "${tests[@]}"; do
  ( set -e; "$name" )
  rc=$?
  if [ "$rc" -eq 0 ]; then
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
