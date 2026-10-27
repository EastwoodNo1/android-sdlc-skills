#!/usr/bin/env bash

CAP_SID=5e1f0c2a-0000-4000-8000-0000000000a1
CAP_TRANSCRIPT="$FIXTURES_DIR/claude/$CAP_SID.jsonl"

cap_setup() {
  REPO="${1:-$T/repo}"
  new_repo "$REPO"
  . "$SCRIPTS_DIR/lib.sh"
  STATE=$(adlc_state_dir "$REPO")
  mkdir -p "$T/tmp"
  export TMPDIR="$T/tmp"
  mkdir -p "$STATE"
  export ADLC_CLAUDE_BIN="$TESTS_DIR/stub/claude"
  export ADLC_STUB_LOG="$T/stub.log"
  unset ADLC_STUB_FAIL ADLC_RUNNER_MODE ADLC_PLUGIN_DIR
  NOTE="$STATE/staged/2026-01-01-5e1f0c2a.md"
}

cap_run() {
  bash "$SCRIPTS_DIR/capture.sh" claude "$CAP_SID" "$CAP_TRANSCRIPT" "$REPO" >"$T/out" 2>&1
}

t_capture_writes_staged_note() {
  cap_setup
  cap_run
  [ -s "$NOTE" ]
  assert_contains "$(cat "$NOTE")" "# stub note"
}

t_capture_records_captured_id() {
  cap_setup
  cap_run
  grep -qxF "$CAP_SID" "$STATE/captured"
}

t_capture_removes_digest_on_success() {
  cap_setup
  cap_run
  [ ! -e "$STATE/digests/$CAP_SID.md" ]
}

t_capture_redacts_email_and_home_path() {
  cap_setup
  cap_run
  assert_not_contains "$NOTE" "@"
  assert_not_contains "$NOTE" "/Users/x"
  assert_contains "$(cat "$NOTE")" "[redacted]"
}

t_capture_redacts_deny_list_term() {
  cap_setup
  printf 'STUB Note\n\nnomatch\n' >"$STATE/deny-list"
  cap_run
  assert_not_contains "$NOTE" "stub note"
  assert_contains "$(cat "$NOTE")" "# [redacted]"
}

t_capture_keeps_digest_on_runner_failure() {
  cap_setup
  rc=0
  ADLC_STUB_FAIL=1 cap_run || rc=$?
  assert_status 1 "$rc"
  [ -s "$STATE/digests/$CAP_SID.md" ]
  if [ -f "$STATE/captured" ]; then
    assert_not_contains "$STATE/captured" "$CAP_SID"
  fi
}

t_capture_respects_lock() {
  cap_setup
  mkdir "$STATE/lock"
  rc=0
  cap_run || rc=$?
  assert_status 0 "$rc"
  assert_contains "$(cat "$T/out")" "busy"
  [ ! -e "$NOTE" ]
  [ -d "$STATE/lock" ]
}

t_capture_breaks_stale_lock() {
  cap_setup
  mkdir "$STATE/lock"
  stamp=$( (date -v-31M +%Y%m%d%H%M 2>/dev/null) || date -d '31 minutes ago' +%Y%m%d%H%M)
  touch -t "$stamp" "$STATE/lock"
  cap_run
  [ -s "$NOTE" ]
  [ ! -e "$STATE/lock" ]
}

t_capture_handles_space_in_repo_path() {
  cap_setup "$T/my repo"
  cap_run
  [ -s "$NOTE" ]
}

t_capture_passes_model_and_loop_guard() {
  cap_setup
  cap_run
  assert_contains "$(cat "$ADLC_STUB_LOG")" "--model sonnet"
  assert_contains "$(cat "$ADLC_STUB_LOG")" "disableAllHooks"
  assert_contains "$(cat "$ADLC_STUB_LOG")" "Edit(//"
  assert_not_contains "$ADLC_STUB_LOG" "Write("
}

t_capture_rejects_unknown_runner_mode() {
  cap_setup
  rc=0
  ADLC_RUNNER_MODE=bogus cap_run || rc=$?
  assert_status 1 "$rc"
}

t_capture_prunes_logs_beyond_50() {
  cap_setup
  mkdir -p "$STATE/log"
  i=1
  while [ "$i" -le 55 ]; do
    : >"$STATE/log/old$i.log"
    touch -t "2025010100$(printf '%02d' "$i")" "$STATE/log/old$i.log"
    i=$((i + 1))
  done
  : >"$STATE/log/$CAP_SID.log"
  cap_run
  assert_eq 50 "$(find "$STATE/log" -name '*.log' | wc -l | tr -d ' ')"
  [ -e "$STATE/log/$CAP_SID.log" ]
  [ ! -e "$STATE/log/old1.log" ]
}

t_capture_fail_after_write_leaves_nothing_staged() {
  cap_setup
  rc=0
  ADLC_STUB_FAIL_AFTER_WRITE=1 cap_run || rc=$?
  assert_status 1 "$rc"
  assert_eq 0 "$(find "$STATE/staged" -type f | wc -l | tr -d ' ')"
  assert_eq 0 "$(find "$T/tmp" -type f | wc -l | tr -d ' ')"
}

t_capture_non_utf8_note_is_redacted() {
  cap_setup
  ADLC_STUB_BAD_BYTE=1 LC_ALL=en_US.UTF-8 cap_run
  [ -s "$NOTE" ]
  assert_not_contains "$NOTE" "someone@"
  assert_contains "$(cat "$NOTE")" "[redacted]"
}

t_capture_success_leaves_only_one_staged_file() {
  cap_setup
  cap_run
  assert_eq 1 "$(find "$STATE/staged" -type f | wc -l | tr -d ' ')"
  assert_eq 0 "$(find "$T/tmp" -type f | wc -l | tr -d ' ')"
}

t_capture_redaction_failure_leaves_nothing_staged() {
  cap_setup
  printf 'term\n' >"$STATE/deny-list"
  chmod 000 "$STATE/deny-list"
  rc=0
  cap_run || rc=$?
  assert_status 1 "$rc"
  assert_eq 0 "$(find "$STATE/staged" -type f | wc -l | tr -d ' ')"
  assert_eq 0 "$(find "$T/tmp" -type f | wc -l | tr -d ' ')"
}

t_capture_rejects_invalid_session_id() {
  cap_setup
  local rc=0
  bash "$SCRIPTS_DIR/capture.sh" claude "../evil" "$CAP_TRANSCRIPT" "$REPO" >"$T/out" 2>&1 || rc=$?
  [ "$rc" -eq 1 ]
  assert_contains "$(cat "$T/out")" "invalid session id"
  [ ! -e "$STATE/evil.md" ]
}
