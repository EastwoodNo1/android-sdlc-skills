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

if ! due=$(adlc_capture_due "$harness" "$state" "$session_id" "$transcript"); then
  if adlc_capture_mark "$state" "$session_id" >/dev/null; then
    say "already captured $session_id"
  else
    say "fewer than 3 prompts in $session_id"
  fi
  exit 0
fi
read -r after through part <<EOF2
$due
EOF2

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

digest="$workdir/digest.md"
bash "$here/digest.sh" --format claude --prompts "$after:$through" "$transcript" "$digest" || fail_capture "digest failed"

day=$(sed -n 's/^Start: //p' "$digest" | head -n 1 | cut -c1-10)
case "$day" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) day=$(date +%Y-%m-%d) ;;
esac
suffix=
[ "$part" -gt 1 ] && suffix="-$part"
note="$state/staged/$day-$(printf '%s' "$session_id" | cut -c1-8)$suffix.md"

prompt="MODE: capture
DIGEST: $digest
NOTE: $work
REPO: $top
SESSION: $session_id
PART: $part
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
      --allowedTools "Read(/${workdir}/**)" "Read(/${top}/**)" \
      "Grep(/${workdir}/**)" "Grep(/${top}/**)" "Glob(/${workdir}/**)" "Glob(/${top}/**)" \
      "Edit(/${workdir}/**)" \
      --disallowedTools "Read(/${top}/.git/**)" \
      -- "$prompt" </dev/null
) || rc=$?

[ "$rc" -eq 0 ] || fail_capture "runner failed with status $rc"
[ -s "$work" ] || fail_capture "note missing or empty: $work"
adlc_redact "$work" "$state" || fail_capture "redaction failed"
mv "$work" "$note" || fail_capture "could not move note into staged"

printf '%s\t%s\t%s\n' "$session_id" "$through" "$part" >>"$state/captured"
say "captured $session_id -> $note"
prune_logs
exit 0
