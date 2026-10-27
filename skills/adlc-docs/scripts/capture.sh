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
case "$session_id" in
  *[!A-Za-z0-9-]*)
    say "invalid session id"
    exit 1
    ;;
esac
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

mkdir -p "$state/staged" "$state/log" || exit 1
lock="$state/lock"

if [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
  say "breaking stale lock"
  rmdir "$lock" 2>/dev/null || rm -rf "$lock"
fi
if ! mkdir "$lock" 2>/dev/null; then
  say "busy: another capture holds the lock"
  exit 0
fi
workdir=
cleanup() {
  [ -n "$workdir" ] && rm -rf "$workdir" 2>/dev/null
  rmdir "$lock" 2>/dev/null
}
trap cleanup EXIT
workdir=$(mktemp -d "${TMPDIR:-/tmp}/adlc-work.XXXXXX") || {
  say "could not create work directory"
  exit 1
}
workdir=$(cd "$workdir" && pwd -P) || exit 1
work="$workdir/$session_id.md"

if [ -f "$state/captured" ] && grep -qxF -- "$session_id" "$state/captured"; then
  say "already captured $session_id"
  exit 0
fi

fail_capture() {
  say "$*"
  printf '%s\n' "$session_id" >>"$state/failed"
  prune_logs
  exit 1
}

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

digest="$workdir/digest.md"
note="$state/staged/$day-$(printf '%s' "$session_id" | cut -c1-8).md"

bash "$here/digest.sh" --format claude "$transcript" "$digest" || fail_capture "digest failed"

prompt="MODE: capture
DIGEST: $digest
NOTE: $work
REPO: $top
SESSION: $session_id
HARNESS: $harness"

claude_bin=${ADLC_CLAUDE_BIN:-claude}
plugin_args=()
if [ -n "${ADLC_PLUGIN_DIR:-}" ]; then
  plugin_args=(--plugin-dir "$ADLC_PLUGIN_DIR")
fi

rm -f "$work"
rc=0
(
  cd "$top" &&
    ADLC_CAPTURE=1 "$claude_bin" -p --agent android-sdlc:adlc-documenter --model sonnet \
      ${plugin_args[@]+"${plugin_args[@]}"} \
      --settings '{"disableAllHooks":true}' --no-session-persistence \
      --permission-mode dontAsk \
      --allowedTools "Read(/${workdir}/**)" "Read(/${top}/**)" "Edit(/${workdir}/**)" \
      --disallowedTools "Read(/${top}/.git/**)" \
      -- "$prompt" </dev/null
) || rc=$?

[ "$rc" -eq 0 ] || fail_capture "runner failed with status $rc"
[ -s "$work" ] || fail_capture "note missing or empty: $work"
adlc_redact "$work" "$state" || fail_capture "redaction failed"
mv "$work" "$note" || fail_capture "could not move note into staged"

printf '%s\n' "$session_id" >>"$state/captured"
say "captured $session_id -> $note"
prune_logs
exit 0
