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

t_capture_records_captured_id_with_watermark() {
  cap_setup
  cap_run
  assert_eq "$(printf '%s\t3\t1' "$CAP_SID")" "$(cat "$STATE/captured")"
}

cap_resumable() {
  cp "$CAP_TRANSCRIPT" "$T/s.jsonl"
  CAP_TRANSCRIPT="$T/s.jsonl"
}

cap_append_prompts() {
  local n=$1 i=1
  while [ "$i" -le "$n" ]; do
    printf '{"type":"user","isMeta":null,"timestamp":"2026-01-02T09:00:0%s.000Z","sessionId":"%s","message":{"role":"user","content":"resumed prompt %s"}}\n' "$i" "$CAP_SID" "$i" >>"$CAP_TRANSCRIPT"
    printf '{"type":"assistant","timestamp":"2026-01-02T09:00:0%s.500Z","message":{"role":"assistant","content":[{"type":"text","text":"resumed reply %s"}]}}\n' "$i" "$i" >>"$CAP_TRANSCRIPT"
    i=$((i + 1))
  done
}

t_capture_resumed_session_writes_second_note_with_only_new_part() {
  cap_setup
  cap_resumable
  cap_run
  [ -s "$NOTE" ]
  cap_append_prompts 3
  ADLC_STUB_DIGEST_COPY="$T/digest2.md" cap_run
  [ -s "$STATE/staged/2026-01-02-5e1f0c2a-2.md" ] || fail "no second note: $(ls "$STATE/staged"; cat "$T/out")"
  assert_eq 1 "$(grep -c "^PART: 2$" "$ADLC_STUB_LOG")"
  assert_contains "$(cat "$T/digest2.md")" "resumed prompt 1"
  assert_contains "$(cat "$T/digest2.md")" "resumed prompt 3"
  assert_contains "$(cat "$T/digest2.md")" "resumed reply 3"
  assert_not_contains "$T/digest2.md" "Add a retry to the fetch helper"
  assert_not_contains "$T/digest2.md" "outline the parser"
  assert_eq 2 "$(find "$STATE/staged" -type f | wc -l | tr -d ' ')"
  assert_eq "$(printf '%s\t6\t2' "$CAP_SID")" "$(tail -n 1 "$STATE/captured")"
}

t_capture_third_part_after_more_growth() {
  cap_setup
  cap_resumable
  cap_run
  cap_append_prompts 3
  cap_run
  cap_append_prompts 4
  ADLC_STUB_DIGEST_COPY="$T/digest3.md" cap_run
  [ -s "$STATE/staged/2026-01-02-5e1f0c2a-3.md" ] || fail "no third note: $(ls "$STATE/staged")"
  assert_eq 4 "$(grep -c '^## Human' "$T/digest3.md")"
  assert_eq "$(printf '%s\t10\t3' "$CAP_SID")" "$(tail -n 1 "$STATE/captured")"
}

t_capture_resumed_session_with_little_growth_is_skipped() {
  cap_setup
  cap_resumable
  cap_run
  cap_append_prompts 2
  cap_run
  assert_contains "$(cat "$T/out")" "already captured"
  assert_eq 1 "$(find "$STATE/staged" -type f | wc -l | tr -d ' ')"
  assert_eq 1 "$(wc -l <"$STATE/captured" | tr -d ' ')"
}

t_capture_bare_id_is_treated_as_captured_to_current_end() {
  cap_setup
  cap_resumable
  printf '%s\n' "$CAP_SID" >"$STATE/captured"
  cap_run
  assert_contains "$(cat "$T/out")" "already captured"
  [ ! -e "$STATE/staged" ] || assert_eq 0 "$(find "$STATE/staged" -type f | wc -l | tr -d ' ')"
  assert_eq "$(printf '%s\t3\t1' "$CAP_SID")" "$(tail -n 1 "$STATE/captured")"
  cap_append_prompts 3
  ADLC_STUB_DIGEST_COPY="$T/digest2.md" cap_run
  [ -s "$STATE/staged/2026-01-02-5e1f0c2a-2.md" ] || fail "no second note: $(cat "$T/out")"
  assert_not_contains "$T/digest2.md" "Add a retry to the fetch helper"
}

t_capture_keeps_digest_out_of_state_dir() {
  cap_setup
  cap_run
  [ ! -e "$STATE/digests" ]
  assert_contains "$(cat "$ADLC_STUB_LOG")" "DIGEST: $(cd "$T/tmp" && pwd -P)/adlc-work."
  assert_eq 0 "$(find "$T/tmp" -mindepth 1 | wc -l | tr -d ' ')"
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

t_capture_runner_failure_records_failed_and_cleans_up() {
  cap_setup
  rc=0
  ADLC_STUB_FAIL=1 cap_run || rc=$?
  assert_status 1 "$rc"
  [ ! -e "$STATE/digests" ]
  assert_eq 0 "$(find "$T/tmp" -mindepth 1 | wc -l | tr -d ' ')"
  assert_eq "$CAP_SID" "$(cat "$STATE/failed")"
  if [ -f "$STATE/captured" ]; then
    assert_not_contains "$STATE/captured" "$CAP_SID"
  fi
}

t_capture_each_failure_appends_one_line() {
  cap_setup
  rc=0
  ADLC_STUB_FAIL=1 cap_run || rc=$?
  ADLC_STUB_FAIL=1 cap_run || rc=$?
  assert_eq 2 "$(grep -cxF "$CAP_SID" "$STATE/failed")"
}

t_capture_success_does_not_record_failed() {
  cap_setup
  cap_run
  [ ! -e "$STATE/failed" ]
}

t_capture_note_missing_records_failed() {
  cap_setup
  rc=0
  ADLC_STUB_NO_WRITE=1 cap_run || rc=$?
  assert_status 1 "$rc"
  assert_eq 1 "$(grep -cxF "$CAP_SID" "$STATE/failed")"
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
  assert_contains "$(cat "$ADLC_STUB_LOG")" "PART: 1"
  assert_contains "$(cat "$ADLC_STUB_LOG")" "disableAllHooks"
  assert_contains "$(cat "$ADLC_STUB_LOG")" "Edit(//"
  assert_not_contains "$ADLC_STUB_LOG" "Write("
}

t_capture_permissions_are_path_scoped() {
  cap_setup
  cap_run
  local top args
  top=$(cd "$REPO" && pwd -P)
  args=$(cat "$ADLC_STUB_LOG")
  assert_contains "$args" "Read(/$top/**)"
  assert_contains "$args" "Read(/$(cd "$T/tmp" && pwd -P)/adlc-work."
  assert_contains "$args" "Edit(/$(cd "$T/tmp" && pwd -P)/adlc-work."
  assert_contains "$args" "--disallowedTools Read(/$top/.git/**)"
  assert_not_contains "$ADLC_STUB_LOG" "Bash("
  assert_contains "$args" "Grep(/$top/**)"
  assert_contains "$args" "Glob(/$top/**)"
  assert_contains "$args" "Grep(/$(cd "$T/tmp" && pwd -P)/adlc-work."
  assert_contains "$args" "Glob(/$(cd "$T/tmp" && pwd -P)/adlc-work."
  assert_not_contains "$ADLC_STUB_LOG" "allowedTools Read "
  assert_not_contains "$ADLC_STUB_LOG" " Grep "
  assert_not_contains "$ADLC_STUB_LOG" " Glob "
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
  assert_eq 0 "$(find "$T/tmp" -mindepth 1 | wc -l | tr -d ' ')"
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
  assert_eq 0 "$(find "$T/tmp" -mindepth 1 | wc -l | tr -d ' ')"
}

t_capture_redaction_failure_leaves_nothing_staged() {
  cap_setup
  printf 'term\n' >"$STATE/deny-list"
  chmod 000 "$STATE/deny-list"
  rc=0
  cap_run || rc=$?
  assert_status 1 "$rc"
  assert_eq 0 "$(find "$STATE/staged" -type f | wc -l | tr -d ' ')"
  assert_eq 0 "$(find "$T/tmp" -mindepth 1 | wc -l | tr -d ' ')"
}

t_capture_rejects_invalid_session_id() {
  cap_setup
  local rc=0
  bash "$SCRIPTS_DIR/capture.sh" claude "../evil" "$CAP_TRANSCRIPT" "$REPO" >"$T/out" 2>&1 || rc=$?
  [ "$rc" -eq 1 ]
  assert_contains "$(cat "$T/out")" "invalid session id"
  [ ! -e "$STATE/evil.md" ]
}

t_capture_redacts_secret_and_logs_class() {
  cap_setup
  printf 'PROJ\n' >"$STATE/issue-keys"
  ADLC_STUB_SECRET=1 cap_run
  assert_not_contains "$NOTE" "PROJ-42"
  assert_contains "$(cat "$NOTE")" "REQ-001"
  assert_contains "$(cat "$STATE/log/redactions.log")" "jira-key"
  assert_contains "$(cat "$STATE/log/redactions.log")" "email"
}
