#!/usr/bin/env bash

SID=5e1f0c2a-0000-4000-8000-0000000000a1
FIXTURE_TRANSCRIPT="$FIXTURES_DIR/claude/$SID.jsonl"

new_repo() {
  git init -q "$1"
  git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
}

t_digest_matches_expected() {
  bash "$SCRIPTS_DIR/digest.sh" --format claude "$FIXTURE_TRANSCRIPT" "$T/out.md"
  assert_file_eq "$FIXTURES_DIR/claude/expected-digest.md" "$T/out.md"
}

t_digest_caps_long_assistant_message() {
  bash "$SCRIPTS_DIR/digest.sh" --format claude "$FIXTURE_TRANSCRIPT" "$T/out.md"
  line=$(grep '…\[truncated\]$' "$T/out.md")
  [ -n "$line" ]
  len=$(printf '%s' "$line" | LC_ALL=C wc -c | tr -d ' ')
  assert_le 1520 "$len" "truncated line length in bytes"
}

t_digest_excludes_noise() {
  bash "$SCRIPTS_DIR/digest.sh" --format claude "$FIXTURE_TRANSCRIPT" "$T/out.md"
  assert_not_contains "$T/out.md" synthetic "noise leaked"
  assert_not_contains "$T/out.md" command- "wrapper leaked"
}

t_prompt_count_ignores_meta_and_tool_results() {
  . "$SCRIPTS_DIR/lib.sh"
  assert_eq 3 "$(adlc_human_prompt_count claude "$FIXTURE_TRANSCRIPT")"
}

t_prompt_count_unknown_harness_fails() {
  . "$SCRIPTS_DIR/lib.sh"
  rc=0
  adlc_human_prompt_count nope "$FIXTURE_TRANSCRIPT" >/dev/null || rc=$?
  assert_status 1 "$rc"
}

t_digest_empty_args_command_renders_name() {
  printf '%s\n' '{"type":"user","timestamp":"2026-01-01T00:00:00Z","sessionId":"s","message":{"role":"user","content":"<command-name>/model</command-name>\n<command-args></command-args>"}}' >"$T/s.jsonl"
  bash "$SCRIPTS_DIR/digest.sh" --format claude "$T/s.jsonl" "$T/out.md"
  assert_contains "$(cat "$T/out.md")" "## Human
/model"
}

t_digest_tolerates_malformed_lines() {
  printf '%s\n' 'not json' '{"type":"user","message":{"role":"user","content":"hello"}}' >"$T/s.jsonl"
  bash "$SCRIPTS_DIR/digest.sh" --format claude "$T/s.jsonl" "$T/out.md"
  assert_contains "$(cat "$T/out.md")" "## Human
hello"
  assert_contains "$(cat "$T/out.md")" "Start: unknown"
}

t_digest_total_cap_trims_ai_from_middle() {
  big=$(i=0; while [ $i -lt 1400 ]; do printf 'x'; i=$((i + 1)); done)
  {
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"first prompt"}}'
    i=0
    while [ $i -lt 200 ]; do
      printf '{"type":"assistant","message":{"content":[{"type":"text","text":"m%03d %s"}]}}\n' "$i" "$big"
      i=$((i + 1))
      if [ $i -eq 100 ]; then
        printf '%s\n' '{"type":"user","message":{"role":"user","content":"middle prompt"}}'
      fi
    done
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"last prompt"}}'
  } >"$T/big.jsonl"
  bash "$SCRIPTS_DIR/digest.sh" --format claude "$T/big.jsonl" "$T/out.md"
  size=$(wc -c <"$T/out.md" | tr -d ' ')
  assert_le 150000 "$size" "digest bytes"
  assert_eq 3 "$(grep -c '^## Human$' "$T/out.md")"
  grep -q 'first prompt' "$T/out.md"
  grep -q 'middle prompt' "$T/out.md"
  grep -q 'last prompt' "$T/out.md"
  grep -q 'm000 ' "$T/out.md"
  grep -q 'm199 ' "$T/out.md"
  assert_not_contains "$T/out.md" 'm100 ' "middle message kept"
  grep -q 'omitted to fit size cap' "$T/out.md"
}

t_state_dir_in_repo_and_worktree() {
  . "$SCRIPTS_DIR/lib.sh"
  new_repo "$T/repo"
  git -C "$T/repo" worktree add -q "$T/wt" -b side
  root=$(cd "$T/repo" && pwd -P)
  assert_eq "$root/.git/adlc" "$(adlc_state_dir "$T/repo")"
  assert_eq "$root/.git/adlc" "$(adlc_state_dir "$T/wt")"
  assert_eq "$root" "$(adlc_toplevel "$T/repo")"
}

t_state_dir_outside_git_fails() {
  . "$SCRIPTS_DIR/lib.sh"
  mkdir -p "$T/plain"
  rc=0
  adlc_state_dir "$T/plain" >/dev/null || rc=$?
  assert_status 1 "$rc"
}

t_opted_in_by_process_file_writes_enabled() {
  . "$SCRIPTS_DIR/lib.sh"
  new_repo "$T/repo"
  rc=0
  adlc_opted_in "$T/repo" || rc=$?
  assert_status 1 "$rc"
  mkdir -p "$T/repo/docs/adlc"
  : >"$T/repo/docs/adlc/ADLC_PROCESS.md"
  adlc_opted_in "$T/repo"
  [ -f "$T/repo/.git/adlc/enabled" ]
}

t_disabled_by_env_or_file() {
  . "$SCRIPTS_DIR/lib.sh"
  new_repo "$T/repo"
  rc=0
  (unset ADLC_DISABLE; adlc_disabled "$T/repo") || rc=$?
  assert_status 1 "$rc"
  ADLC_DISABLE=1 adlc_disabled "$T/repo"
  mkdir -p "$T/repo/.git/adlc"
  : >"$T/repo/.git/adlc/disabled"
  (unset ADLC_DISABLE; adlc_disabled "$T/repo")
}
