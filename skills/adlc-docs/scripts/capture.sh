#!/usr/bin/env bash
set -u

harness=${1:-}
session_id=${2:-}
transcript=${3:-}
cwd=${4:-}

here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

say() {
  printf 'adlc-docs capture: %s\n' "$*"
}

if [ -z "$harness" ] || [ -z "$session_id" ] || [ -z "$transcript" ] || [ -z "$cwd" ]; then
  say "usage: capture.sh <harness> <session_id> <transcript_path> <cwd>"
  exit 1
fi
[ "$harness" = "claude" ] || {
  say "unsupported harness $harness"
  exit 1
}
[ -f "$transcript" ] || {
  say "no such transcript $transcript"
  exit 1
}

mode=${ADLC_RUNNER_MODE:-agent}
[ "$mode" = "agent" ] || {
  say "unsupported ADLC_RUNNER_MODE $mode"
  exit 1
}

state=$(adlc_state_dir "$cwd") || {
  say "not a git repository: $cwd"
  exit 1
}
top=$(adlc_toplevel "$cwd") || {
  say "no toplevel for $cwd"
  exit 1
}

mkdir -p "$state/staged" "$state/digests" "$state/log" || exit 1
lock="$state/lock"

if [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
  say "breaking stale lock"
  rmdir "$lock" 2>/dev/null || rm -rf "$lock"
fi
if ! mkdir "$lock" 2>/dev/null; then
  say "busy: another capture holds the lock"
  exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

if [ -f "$state/captured" ] && grep -qxF -- "$session_id" "$state/captured"; then
  say "already captured $session_id"
  exit 0
fi

prune_logs() {
  local f g newer
  for f in "$state/log"/*.log; do
    [ -f "$f" ] || continue
    newer=0
    for g in "$state/log"/*.log; do
      [ "$g" -nt "$f" ] && newer=$((newer + 1))
    done
    [ "$newer" -ge 50 ] && rm -f "$f"
  done
  return 0
}

ts=$(jq -Rr 'fromjson? | objects | .timestamp? // empty | strings' <"$transcript" 2>/dev/null | head -n 1)
day=$(printf '%s' "$ts" | cut -c1-10)
case "$day" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) day=$(date +%Y-%m-%d) ;;
esac

digest="$state/digests/$session_id.md"
note="$state/staged/$day-$(printf '%s' "$session_id" | cut -c1-8).md"

bash "$here/digest.sh" --format claude "$transcript" "$digest" || {
  say "digest failed"
  prune_logs
  exit 1
}

prompt="MODE: capture
DIGEST: $digest
NOTE: $note
REPO: $top
SESSION: $session_id
HARNESS: $harness"

claude_bin=${ADLC_CLAUDE_BIN:-claude}
plugin_args=()
if [ -n "${ADLC_PLUGIN_DIR:-}" ]; then
  plugin_args=(--plugin-dir "$ADLC_PLUGIN_DIR")
fi

rm -f "$note"
rc=0
(
  cd "$top" &&
    ADLC_CAPTURE=1 "$claude_bin" -p --agent android-sdlc:adlc-documenter --model sonnet \
      ${plugin_args[@]+"${plugin_args[@]}"} \
      --settings '{"disableAllHooks":true}' --no-session-persistence \
      --permission-mode dontAsk \
      --allowedTools "Read" "Grep" "Glob" "Write(/${state}/staged/**)" \
      "Bash(git log:*)" "Bash(git show:*)" "Bash(gh pr view:*)" "Bash(gh pr list:*)" \
      -- "$prompt"
) || rc=$?

if [ "$rc" -ne 0 ]; then
  say "runner failed with status $rc"
  prune_logs
  exit 1
fi
if [ ! -s "$note" ]; then
  say "note missing or empty: $note"
  prune_logs
  exit 1
fi

adlc_redact "$note" "$state" || {
  say "redaction failed"
  prune_logs
  exit 1
}

printf '%s\n' "$session_id" >>"$state/captured"
rm -f "$digest"
say "captured $session_id -> $note"
prune_logs
exit 0
