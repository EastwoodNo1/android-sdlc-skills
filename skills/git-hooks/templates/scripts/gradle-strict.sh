#!/bin/sh
cd "$(dirname "$0")/.." || exit 1
out=$(mktemp) || exit 1
st=$(mktemp) || exit 1
trap 'rm -f "$out" "$st"' EXIT
{ ./gradlew "$@" --warning-mode=all 2>&1; echo $? > "$st"; } | tee "$out"
status=$(cat "$st")
if [ "$status" -ne 0 ]; then
  exit "$status"
fi
bad=$(grep -iE 'deprecat|scheduled to be removed' "$out" \
  | grep -vF 'The Configuration.setVisible(boolean) method has been deprecated.' \
  | grep -vE '^Deprecated Gradle features were used in this build')
if [ -n "$bad" ]; then
  echo "gradle-strict: unexpected deprecation:" >&2
  echo "$bad" >&2
  exit 1
fi
