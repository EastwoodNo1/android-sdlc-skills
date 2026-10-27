#!/usr/bin/env bash

rd_setup() {
  mkdir -p "$T/state"
  RD_STATE="$T/state"
  RD_FILE="$T/note.md"
  . "$SCRIPTS_DIR/lib.sh"
}

rd_check() {
  local label=$1 text=$2 secret=$3
  rd_setup
  printf 'before %s after\n' "$text" >"$RD_FILE"
  adlc_redact "$RD_FILE" "$RD_STATE"
  assert_not_contains "$RD_FILE" "$secret" "$label leaked"
  assert_contains "$(cat "$RD_FILE")" "before [redacted] after"
  assert_contains "$(cat "$RD_STATE/log/redactions.log")" "$label"
  assert_not_contains "$RD_STATE/log/redactions.log" "$secret" "log leaked $label"
}

t_redact_github_token() {
  local s
  s="ghp_$(rep a 24)"
  rd_check github-token "$s" "$s"
}

t_redact_github_pat() {
  local s
  s="github_pat_$(rep B 22)_$(rep c 10)"
  rd_check github-pat "$s" "$s"
}

t_redact_api_key() {
  local s
  s="sk-$(rep d 24)"
  rd_check api-key "$s" "$s"
}

t_redact_api_key_not_inside_words() {
  rd_setup
  printf 'branch task-implement-redaction-patterns-now\n' >"$RD_FILE"
  adlc_redact "$RD_FILE" "$RD_STATE"
  assert_contains "$(cat "$RD_FILE")" "task-implement-redaction-patterns-now"
}

t_redact_aws_key() {
  local s
  s="AKIA$(rep Q 16)"
  rd_check aws-key "$s" "$s"
}

t_redact_slack_token() {
  local s
  s="xoxb-$(rep 1 12)-$(rep z 6)"
  rd_check slack-token "$s" "$s"
}

t_redact_bearer_token() {
  local s
  s="$(rep e 20).$(rep f 5)"
  rd_check bearer-token "Bearer $s" "$s"
}

t_redact_jwt() {
  local s
  s="eyJ$(rep g 12).$(rep h 12).$(rep i 12)"
  rd_check jwt "$s" "$s"
}

t_redact_private_key_block() {
  rd_setup
  {
    printf 'start\n'
    printf '%s\n' "-----BEGIN RSA PRIVATE KEY-----"
    printf 'MIIEvQIBADANBgkqhkiG9w0BAQEFAASC\n'
    printf '%s\n' "-----END RSA PRIVATE KEY-----"
    printf 'end\n'
  } >"$RD_FILE"
  adlc_redact "$RD_FILE" "$RD_STATE"
  assert_eq "start
[redacted]
end" "$(cat "$RD_FILE")"
  assert_contains "$(cat "$RD_STATE/log/redactions.log")" "private-key"
}

t_redact_jira_key() {
  rd_check jira-key "PROJ-123" "PROJ-123"
}

t_redact_jira_key_inside_sentence_and_twice() {
  rd_setup
  printf 'see ABC-1, and XY2-77.\n' >"$RD_FILE"
  adlc_redact "$RD_FILE" "$RD_STATE"
  assert_eq "see [redacted], and [redacted]." "$(cat "$RD_FILE")"
}

t_redact_keeps_documentation_ids() {
  rd_setup
  printf 'REQ-001 AC-2 DEC-013 DES-4 IMP-5 TEST-6 PROMPT-007 CYCLE-001\n' >"$RD_FILE"
  adlc_redact "$RD_FILE" "$RD_STATE"
  assert_eq "REQ-001 AC-2 DEC-013 DES-4 IMP-5 TEST-6 PROMPT-007 CYCLE-001" "$(cat "$RD_FILE")"
  [ ! -s "$RD_STATE/log/redactions.log" ] || fail "unexpected log: $(cat "$RD_STATE/log/redactions.log")"
}

t_redact_keeps_lowercase_and_mid_word_keys() {
  rd_setup
  printf 'abc-12 xABC-12 ABC-12x\n' >"$RD_FILE"
  adlc_redact "$RD_FILE" "$RD_STATE"
  assert_eq "abc-12 xABC-12 ABC-12x" "$(cat "$RD_FILE")"
}

t_redact_logs_one_line_per_class() {
  rd_setup
  printf 'a@b.example and c@d.example\nPROJ-1\n' >"$RD_FILE"
  adlc_redact "$RD_FILE" "$RD_STATE"
  assert_eq 2 "$(wc -l <"$RD_STATE/log/redactions.log" | tr -d ' ')"
  assert_contains "$(cat "$RD_STATE/log/redactions.log")" "email"
  assert_contains "$(cat "$RD_STATE/log/redactions.log")" "jira-key"
}

t_redact_logs_deny_list_class() {
  rd_setup
  printf 'secretterm\n' >"$RD_STATE/deny-list"
  printf 'has SecretTerm here\n' >"$RD_FILE"
  adlc_redact "$RD_FILE" "$RD_STATE"
  assert_eq "has [redacted] here" "$(cat "$RD_FILE")"
  assert_contains "$(cat "$RD_STATE/log/redactions.log")" "deny-list"
  assert_not_contains "$RD_STATE/log/redactions.log" "secretterm"
}
