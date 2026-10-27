#!/usr/bin/env bash

SE_SID=5e1f0c2a-0000-4000-8000-0000000000a1
SE_TRANSCRIPT="$FIXTURES_DIR/claude/$SE_SID.jsonl"

se_setup() {
  REPO="$T/repo"
  git init -q "$REPO"
  git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
  RECORD="$T/record"
  cat >"$T/recorder.sh" <<REC
#!/usr/bin/env bash
{
  printf 'args:'
  for a in "\$@"; do printf ' [%s]' "\$a"; done
  printf '\n'
  printf 'capture=%s\n' "\${ADLC_CAPTURE:-}"
} >>"$RECORD"
REC
  chmod +x "$T/recorder.sh"
  export ADLC_CAPTURE_CMD="$T/recorder.sh"
  unset ADLC_CAPTURE ADLC_DISABLE
}

se_opt_in() {
  mkdir -p "$REPO/docs/adlc"
  : >"$REPO/docs/adlc/ADLC_PROCESS.md"
}

se_run() {
  local harness=$1 transcript=${2:-$SE_TRANSCRIPT} cwd=${3:-$REPO}
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$SE_SID" "$transcript" "$cwd" |
    bash "$SCRIPTS_DIR/session-end.sh" "$harness" >"$T/stdout" 2>"$T/stderr"
}

se_wait_record() {
  local i=0
  while [ ! -s "$RECORD" ] && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  [ -s "$RECORD" ]
}

se_assert_nothing_started() {
  sleep 0.5
  [ ! -e "$RECORD" ] || fail "capture started unexpectedly: $(cat "$RECORD")"
  [ ! -s "$T/stdout" ] || fail "stdout not clean: $(cat "$T/stdout")"
}

t_session_end_not_opted_in_starts_nothing() {
  se_setup
  se_run claude
  se_assert_nothing_started
}

t_session_end_loop_guard_starts_nothing() {
  se_setup
  se_opt_in
  ADLC_CAPTURE=1 se_run claude
  se_assert_nothing_started
}

t_session_end_disabled_file_starts_nothing() {
  se_setup
  se_opt_in
  state=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/adlc
  mkdir -p "$state"
  : >"$state/disabled"
  se_run claude
  se_assert_nothing_started
}

t_session_end_already_captured_starts_nothing() {
  se_setup
  se_opt_in
  state=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/adlc
  mkdir -p "$state"
  printf 'other\n%s\n' "$SE_SID" >"$state/captured"
  se_run claude
  se_assert_nothing_started
}

t_session_end_skips_tool_only_transcript() {
  se_setup
  se_opt_in
  {
    printf '%s\n' '{"type":"user","isMeta":null,"message":{"role":"user","content":"only one prompt"}}'
    printf '%s\n' '{"type":"user","isMeta":null,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"synthetic output"}]}}'
    printf '%s\n' '{"type":"user","isMeta":null,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"synthetic output"}]}}'
  } >"$T/tool-only.jsonl"
  se_run claude "$T/tool-only.jsonl"
  se_assert_nothing_started
}

t_session_end_missing_transcript_starts_nothing() {
  se_setup
  se_opt_in
  se_run claude "$T/nope.jsonl"
  se_assert_nothing_started
}

t_session_end_outside_git_repo_exits_0() {
  se_setup
  mkdir -p "$T/plain"
  status=0
  se_run claude "$SE_TRANSCRIPT" "$T/plain" || status=$?
  assert_status 0 "$status"
  se_assert_nothing_started
}

t_session_end_unknown_harness_exits_0_with_note() {
  se_setup
  se_opt_in
  status=0
  se_run codex || status=$?
  assert_status 0 "$status"
  assert_contains "$(cat "$T/stderr")" "adapter not implemented"
  se_assert_nothing_started
}

t_session_end_opted_in_starts_capture() {
  se_setup
  se_opt_in
  se_run claude
  se_wait_record
  top=$(cd "$REPO" && pwd -P)
  assert_contains "$(cat "$RECORD")" "args: [claude] [$SE_SID] [$SE_TRANSCRIPT] [$REPO]"
  assert_contains "$(cat "$RECORD")" "capture=1"
  [ -n "$top" ]
}

t_session_end_writes_enabled_marker() {
  se_setup
  se_opt_in
  se_run claude
  state=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/adlc
  [ -f "$state/enabled" ] || fail "enabled marker missing"
}

t_session_end_logs_to_session_log() {
  se_setup
  se_opt_in
  printf '#!/usr/bin/env bash\necho hello-log\necho err-log >&2\n' >"$T/logger.sh"
  chmod +x "$T/logger.sh"
  ADLC_CAPTURE_CMD="$T/logger.sh" se_run claude
  state=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/adlc
  i=0
  while ! grep -q err-log "$state/log/$SE_SID.log" 2>/dev/null && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  assert_contains "$(cat "$state/log/$SE_SID.log")" hello-log
  assert_contains "$(cat "$state/log/$SE_SID.log")" err-log
}

t_session_end_returns_under_1s() {
  se_setup
  se_opt_in
  printf '#!/usr/bin/env bash\nsleep 5\n' >"$T/slow.sh"
  chmod +x "$T/slow.sh"
  start=$(date +%s)
  ADLC_CAPTURE_CMD="$T/slow.sh" se_run claude
  end=$(date +%s)
  assert_le 1 $((end - start)) "elapsed seconds"
}
