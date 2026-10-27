#!/usr/bin/env bash

sc_run() {
  local rc=0
  bash "$SCRIPTS_DIR/scan.sh" "$@" >"$T/scan.out" 2>"$T/scan.err" || rc=$?
  return "$rc"
}

t_scan_clean_dir_exits_0() {
  mkdir -p "$T/d/sub"
  printf 'REQ-001 fine text\n' >"$T/d/a.md"
  printf 'nothing here\n' >"$T/d/sub/b.md"
  sc_run "$T/d"
  assert_eq "" "$(cat "$T/scan.out")"
}

t_scan_dirty_dir_exits_1_with_classes() {
  local s rc=0
  s="ghp_$(rep a 24)"
  mkdir -p "$T/d/sub" "$T/state"
  printf 'ABC\n' >"$T/state/issue-keys"
  printf 'ok\nmail x@y.example\n' >"$T/d/a.md"
  printf 'token %s\nTrack ABC-9\npath /Users/zed/x\n' "$s" >"$T/d/sub/b.md"
  sc_run "$T/d" "$T/state" || rc=$?
  assert_status 1 "$rc"
  assert_contains "$(cat "$T/scan.out")" "$T/d/a.md:2: email"
  assert_contains "$(cat "$T/scan.out")" "$T/d/sub/b.md:1: github-token"
  assert_contains "$(cat "$T/scan.out")" "$T/d/sub/b.md:2: jira-key"
  assert_contains "$(cat "$T/scan.out")" "$T/d/sub/b.md:3: home-path"
  assert_not_contains "$T/scan.out" "$s"
  assert_not_contains "$T/scan.out" "x@y.example"
  assert_not_contains "$T/scan.out" "ABC-9"
  assert_not_contains "$T/scan.out" "zed"
}

t_scan_private_key_and_deny_list() {
  local rc=0
  mkdir -p "$T/d" "$T/state"
  printf 'Acme\n\n' >"$T/state/deny-list"
  {
    printf '%s\n' "-----BEGIN PRIVATE KEY-----"
    printf 'body\n'
    printf '%s\n' "-----END PRIVATE KEY-----"
    printf 'we work at ACME corp\n'
  } >"$T/d/a.md"
  sc_run "$T/d" "$T/state" || rc=$?
  assert_status 1 "$rc"
  assert_contains "$(cat "$T/scan.out")" "a.md:1: private-key"
  assert_contains "$(cat "$T/scan.out")" "a.md:4: deny-list"
  assert_not_contains "$T/scan.out" "ACME"
}

t_scan_deny_list_ignored_without_state_dir() {
  mkdir -p "$T/d"
  printf 'we work at ACME corp\n' >"$T/d/a.md"
  sc_run "$T/d"
}

t_scan_does_not_modify_files() {
  local rc=0
  mkdir -p "$T/d"
  printf 'mail x@y.example\n' >"$T/d/a.md"
  sc_run "$T/d" || rc=$?
  assert_eq "mail x@y.example" "$(cat "$T/d/a.md")"
}

t_scan_usage_errors() {
  local rc=0
  sc_run || rc=$?
  assert_status 2 "$rc"
  rc=0
  sc_run "$T/nope" || rc=$?
  assert_status 2 "$rc"
}

t_scan_issue_keys_only_flag_listed_keys() {
  local rc=0
  mkdir -p "$T/d" "$T/state"
  printf 'ABC\n' >"$T/state/issue-keys"
  printf 'ADR-0006 SHA-256 UTF-8 REQ-001\n' >"$T/d/a.md"
  sc_run "$T/d" "$T/state"
  printf 'ABC-123\n' >"$T/d/b.md"
  sc_run "$T/d" "$T/state" || rc=$?
  assert_status 1 "$rc"
  assert_contains "$(cat "$T/scan.out")" "b.md:1: jira-key"
  assert_not_contains "$T/scan.out" "a.md"
  rc=0
  sc_run "$T/d" || rc=$?
  assert_status 0 "$rc"
}
