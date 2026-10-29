#!/usr/bin/env bash
set -euo pipefail

dir="${1:-app/build/outputs/androidTest-results/connected}"

status=0
count=0
while IFS= read -r file; do
  count=$((count + 1))
  suites=$(grep -o '<testsuite [^>]*>' "$file" || true)
  if [ -z "$suites" ]; then
    echo "$file: no testsuite element" >&2
    status=1
    continue
  fi
  while IFS= read -r suite; do
    tests=$(sed -n 's/.* tests="\([0-9]*\)".*/\1/p' <<< "$suite")
    failures=$(sed -n 's/.* failures="\([0-9]*\)".*/\1/p' <<< "$suite")
    errors=$(sed -n 's/.* errors="\([0-9]*\)".*/\1/p' <<< "$suite")
    if [ "${tests:-0}" -le 0 ] || [ "${failures:-1}" -ne 0 ] || [ "${errors:-1}" -ne 0 ]; then
      echo "$file: tests=${tests:-?} failures=${failures:-?} errors=${errors:-?}" >&2
      status=1
    else
      echo "$file: tests=$tests ok"
    fi
  done <<< "$suites"
done < <(find "$dir" -name 'TEST-*.xml' 2>/dev/null | sort)

if [ "$count" -eq 0 ]; then
  echo "no TEST-*.xml under $dir" >&2
  exit 1
fi
exit "$status"
