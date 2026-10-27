#!/usr/bin/env bash
set -u

harness=${1:-claude}

[ "${ADLC_CAPTURE:-}" = "1" ] && exit 0
[ "${ADLC_DISABLE:-}" = "1" ] && exit 0

if [ "$harness" != "claude" ]; then
  printf 'adlc-docs: adapter not implemented for harness %s\n' "$harness" >&2
  exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$session_id" ] && [ -n "$transcript" ] && [ -n "$cwd" ] || exit 0
case "$session_id" in
  *[!A-Za-z0-9-]*) exit 0 ;;
esac

state=$(adlc_state_dir "$cwd") || exit 0
adlc_opted_in "$cwd" || exit 0
[ -f "$state/disabled" ] && exit 0
[ -f "$transcript" ] || exit 0
if [ -f "$state/captured" ] && grep -qxF -- "$session_id" "$state/captured"; then
  exit 0
fi
count=$(adlc_human_prompt_count "$harness" "$transcript" 2>/dev/null) || exit 0
[ "${count:-0}" -ge 3 ] 2>/dev/null || exit 0

capture_cmd=${ADLC_CAPTURE_CMD:-$SCRIPT_DIR/capture.sh}
mkdir -p "$state/log" || exit 0
log="$state/log/$session_id.log"

ADLC_CAPTURE=1 nohup "$capture_cmd" "$harness" "$session_id" "$transcript" "$cwd" </dev/null >>"$log" 2>&1 &
disown 2>/dev/null
exit 0
