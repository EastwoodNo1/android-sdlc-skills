#!/usr/bin/env bash
set -u

harness=${1:-claude}

[ "${ADLC_CAPTURE:-}" = "1" ] && exit 0
[ "${ADLC_DISABLE:-}" = "1" ] && exit 0
[ "$harness" = "claude" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || exit 0

state=$(adlc_state_dir "$cwd") || exit 0
adlc_opted_in "$cwd" || exit 0
[ -f "$state/disabled" ] && exit 0

mkdir -p "$state/log" || exit 0
log="$state/log/backfill.log"
exclude_args=()
case "$session_id" in
  '' | *[!A-Za-z0-9-]*) ;;
  *) exclude_args=(--exclude "$session_id") ;;
esac

ADLC_CAPTURE=1 nohup bash "$SCRIPT_DIR/backfill.sh" --harness "$harness" --project-dir "$cwd" --limit 3 \
  ${exclude_args[@]+"${exclude_args[@]}"} </dev/null >>"$log" 2>&1 &
disown 2>/dev/null

n=0
for note in "$state/staged"/*.md; do
  [ -f "$note" ] && n=$((n + 1))
done
if [ "$n" -gt 0 ]; then
  printf 'ADLC: %s session note(s) waiting for fold-in at the next PR (see android-sdlc:adlc-docs).\n' "$n"
fi
exit 0
