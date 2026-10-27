#!/usr/bin/env bash

bf_slug() {
  printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'
}

bf_setup() {
  REPO="$(cd "$T" && pwd -P)/My.repo"
  git init -q "$REPO"
  git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
  mkdir -p "$REPO/docs/adlc"
  : >"$REPO/docs/adlc/ADLC_PROCESS.md"
  STATE="$REPO/.git/adlc"
  mkdir -p "$STATE"
  : >"$STATE/enabled"
  PROJ="$T/projects"
  RECORD="$T/record"
  : >"$RECORD"
  cat >"$T/recorder.sh" <<REC
#!/usr/bin/env bash
cat >/dev/null
printf '%s %s %s %s capture=%s\n' "\$1" "\$2" "\$3" "\$4" "\${ADLC_CAPTURE:-}" >>"$RECORD"
printf '%s\n' "\$2" >>"$STATE/captured"
REC
  chmod +x "$T/recorder.sh"
  export ADLC_CAPTURE_CMD="$T/recorder.sh" ADLC_PROJECTS_DIR="$PROJ"
  unset ADLC_CAPTURE ADLC_DISABLE
}

bf_session() {
  local dir=$1 id=$2 cwd=$3 ts=$4 prompts=${5:-3} i
  mkdir -p "$PROJ/$dir"
  {
    printf '{"type":"summary","summary":"x"}\n'
    printf '{"type":"user","cwd":"%s","timestamp":"%s","message":{"role":"user","content":"prompt 0"}}\n' "$cwd" "$ts"
    i=1
    while [ "$i" -lt "$prompts" ]; do
      printf '{"type":"user","message":{"role":"user","content":"prompt %s"}}\n' "$i"
      i=$((i + 1))
    done
  } >"$PROJ/$dir/$id.jsonl"
  touch -t 202001010000 "$PROJ/$dir/$id.jsonl"
}

bf_run() {
  (cd "$REPO" && bash "$SCRIPTS_DIR/backfill.sh" "$@") >"$T/stdout" 2>"$T/stderr"
}

t_backfill_captures_only_eligible_oldest_first() {
  bf_setup
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" bbbb-0002 "$REPO" 2026-03-02T00:00:00Z
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z
  bf_session "$d" cccc-0003 "$REPO" 2026-03-03T00:00:00Z
  bf_session "$d" dddd-0004 "$REPO" 2026-03-04T00:00:00Z
  bf_session "$d" eeee-0005 "$REPO" 2026-03-05T00:00:00Z 2
  bf_session "$d" ffff-0006 "$REPO" 2026-03-06T00:00:00Z
  touch "$PROJ/$d/dddd-0004.jsonl"
  printf 'cccc-0003\n' >"$STATE/captured"
  bf_run
  assert_eq 3 "$(wc -l <"$RECORD" | tr -d ' ')"
  assert_eq "claude aaaa-0001 $PROJ/$d/aaaa-0001.jsonl $REPO capture=1" "$(sed -n 1p "$RECORD")"
  assert_eq "claude bbbb-0002 $PROJ/$d/bbbb-0002.jsonl $REPO capture=1" "$(sed -n 2p "$RECORD")"
  assert_contains "$(sed -n 3p "$RECORD")" "ffff-0006"
  assert_eq "captured 3, skipped 3" "$(cat "$T/stdout")"
}

t_backfill_excludes_given_session() {
  bf_setup
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z
  bf_session "$d" bbbb-0002 "$REPO" 2026-03-02T00:00:00Z
  bf_run --exclude aaaa-0001
  assert_eq 1 "$(wc -l <"$RECORD" | tr -d ' ')"
  assert_contains "$(cat "$RECORD")" "bbbb-0002"
  assert_contains "$(cat "$T/stdout")" "captured 1, skipped 1"
}

t_backfill_respects_limit() {
  bf_setup
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z
  bf_session "$d" bbbb-0002 "$REPO" 2026-03-02T00:00:00Z
  bf_session "$d" cccc-0003 "$REPO" 2026-03-03T00:00:00Z
  bf_run --limit 2
  assert_eq 2 "$(wc -l <"$RECORD" | tr -d ' ')"
  assert_contains "$(sed -n 1p "$RECORD")" "aaaa-0001"
  assert_contains "$(sed -n 2p "$RECORD")" "bbbb-0002"
  assert_contains "$(cat "$T/stdout")" "captured 2, skipped 0"
}

t_backfill_matches_worktree_cwd() {
  bf_setup
  git -C "$REPO" -c user.name=t -c user.email=t@t worktree add -q "$REPO-feat" -b feat
  local d wd
  d=$(bf_slug "$REPO")
  wd=$(bf_slug "$REPO-feat")
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z
  bf_session "$wd" bbbb-0002 "$REPO-feat" 2026-03-02T00:00:00Z
  bf_session "$wd" cccc-0003 "$REPO-feat/sub" 2026-03-03T00:00:00Z
  bf_session "$d" dddd-0004 "$T/Other" 2026-03-04T00:00:00Z
  (cd "$REPO-feat" && bash "$SCRIPTS_DIR/backfill.sh") >"$T/stdout" 2>"$T/stderr"
  assert_eq 3 "$(wc -l <"$RECORD" | tr -d ' ')"
  assert_contains "$(sed -n 2p "$RECORD")" "bbbb-0002"
  assert_contains "$(sed -n 3p "$RECORD")" "cccc-0003"
  assert_contains "$(sed -n 1p "$RECORD")" "$REPO capture=1"
}

t_backfill_skips_unsafe_session_ids() {
  bf_setup
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" 'bad id' "$REPO" 2026-03-01T00:00:00Z
  bf_run
  assert_eq 0 "$(wc -l <"$RECORD" | tr -d ' ')"
}

t_backfill_counts_only_newly_captured() {
  bf_setup
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z
  bf_session "$d" bbbb-0002 "$REPO" 2026-03-02T00:00:00Z
  cat >"$T/noop.sh" <<NOOP
#!/usr/bin/env bash
printf '%s\n' "\$2" >>"$RECORD"
if [ "\$2" != aaaa-0001 ]; then printf '%s\n' "\$2" >>"$STATE/captured"; fi
exit 0
NOOP
  chmod +x "$T/noop.sh"
  ADLC_CAPTURE_CMD="$T/noop.sh" bf_run --limit 1
  assert_eq 2 "$(wc -l <"$RECORD" | tr -d ' ')"
  assert_eq "captured 1, skipped 1" "$(cat "$T/stdout")"
}

t_backfill_skips_ids_failed_twice_but_retries_once_failed() {
  bf_setup
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z
  bf_session "$d" bbbb-0002 "$REPO" 2026-03-02T00:00:00Z
  bf_session "$d" cccc-0003 "$REPO" 2026-03-03T00:00:00Z
  printf 'aaaa-0001\naaaa-0001\nbbbb-0002\n' >"$STATE/failed"
  bf_run
  assert_eq 2 "$(wc -l <"$RECORD" | tr -d ' ')"
  assert_contains "$(sed -n 1p "$RECORD")" "bbbb-0002"
  assert_contains "$(sed -n 2p "$RECORD")" "cccc-0003"
  assert_eq "captured 2, skipped 1" "$(cat "$T/stdout")"
}

t_backfill_retries_after_failed_lines_are_deleted() {
  bf_setup
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z
  printf 'aaaa-0001\naaaa-0001\n' >"$STATE/failed"
  bf_run
  assert_eq 0 "$(wc -l <"$RECORD" | tr -d ' ')"
  : >"$STATE/failed"
  bf_run
  assert_eq 1 "$(wc -l <"$RECORD" | tr -d ' ')"
}

t_backfill_records_trivial_ids_and_skips_them_later() {
  bf_setup
  local d
  d=$(bf_slug "$REPO")
  bf_session "$d" aaaa-0001 "$REPO" 2026-03-01T00:00:00Z 2
  bf_session "$d" bbbb-0002 "$REPO" 2026-03-02T00:00:00Z
  bf_run
  assert_eq "aaaa-0001" "$(cat "$STATE/trivial")"
  assert_eq 1 "$(wc -l <"$RECORD" | tr -d ' ')"
  assert_eq "captured 1, skipped 1" "$(cat "$T/stdout")"
  bf_run
  assert_eq "aaaa-0001" "$(cat "$STATE/trivial")"
}

t_backfill_trivial_check_precedes_transcript_parsing() {
  bf_setup
  local d
  d=$(bf_slug "$REPO")
  mkdir -p "$PROJ/$d"
  printf 'not json at all\n' >"$PROJ/$d/aaaa-0001.jsonl"
  touch -t 202001010000 "$PROJ/$d/aaaa-0001.jsonl"
  printf 'aaaa-0001\n' >"$STATE/trivial"
  bf_run
  assert_eq "captured 0, skipped 1" "$(cat "$T/stdout")"
  assert_eq "aaaa-0001" "$(cat "$STATE/trivial")"
}

t_backfill_flag_without_value_prints_usage_and_exits_2() {
  bf_setup
  local flag rc
  for flag in --limit --exclude --project-dir --harness; do
    rc=0
    bf_run "$flag" || rc=$?
    assert_status 2 "$rc" "$flag"
    assert_contains "$(cat "$T/stderr")" "usage"
  done
}
