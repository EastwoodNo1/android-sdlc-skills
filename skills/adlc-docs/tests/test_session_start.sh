#!/usr/bin/env bash

ss_setup() {
  bf_setup
  SID=cccc-0003
}

ss_run() {
  printf '{"session_id":"%s","cwd":"%s"}' "$SID" "$REPO" |
    bash "$SCRIPTS_DIR/session-start.sh" claude >"$T/stdout" 2>"$T/stderr"
}

ss_wait_lines() {
  local i=0
  while [ "$(wc -l <"$RECORD" | tr -d ' ')" -lt "$1" ] && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
  done
}

t_session_start_prints_reminder_when_staged() {
  ss_setup
  mkdir -p "$STATE/staged"
  : >"$STATE/staged/2026-03-01-aaaa.md"
  : >"$STATE/staged/2026-03-02-bbbb.md"
  ss_run
  assert_eq "ADLC: 2 session note(s) waiting for fold-in at the next PR (see android-sdlc:adlc-docs)." "$(cat "$T/stdout")"
}

t_session_start_silent_when_nothing_staged() {
  ss_setup
  ss_run
  assert_eq "" "$(cat "$T/stdout")"
}

t_session_start_silent_when_not_opted_in() {
  ss_setup
  rm -rf "$REPO/docs" "$STATE"
  mkdir -p "$REPO/.git/adlc/staged"
  : >"$REPO/.git/adlc/staged/x.md"
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z
  ss_run
  sleep 0.5
  assert_eq "" "$(cat "$T/stdout")"
  assert_eq 0 "$(wc -l <"$RECORD" | tr -d ' ')"
}

t_session_start_excludes_current_session() {
  ss_setup
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z
  bf_session "$d" cccc-0003 "$REPO" 2026-03-03T00:00:00Z
  ss_run
  ss_wait_lines 1
  sleep 0.5
  assert_eq 1 "$(wc -l <"$RECORD" | tr -d ' ')"
  assert_contains "$(cat "$RECORD")" "aaaa-0001"
}

t_session_start_limits_to_three() {
  ss_setup
  local d n
  d=$(bf_slug "$REPO")
  for n in 1 2 3 4 5; do
    bf_session "$d" "aaaa-000$n" "$REPO" "2026-03-0${n}T00:00:00Z"
  done
  ss_run
  ss_wait_lines 3
  sleep 0.5
  assert_eq 3 "$(wc -l <"$RECORD" | tr -d ' ')"
}

t_session_start_loop_guard_and_disable() {
  ss_setup
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z
  mkdir -p "$STATE/staged"
  : >"$STATE/staged/x.md"
  ADLC_CAPTURE=1 ss_run
  ADLC_DISABLE=1 ss_run
  touch "$STATE/disabled"
  ss_run
  sleep 0.5
  assert_eq "" "$(cat "$T/stdout")"
  assert_eq 0 "$(wc -l <"$RECORD" | tr -d ' ')"
}
