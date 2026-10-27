#!/usr/bin/env bash

ADLC_JQ_DEFS='
def trim: gsub("^\\s+|\\s+$"; "");
def block_text:
  [ .[]
    | select(type == "object" and .type == "text")
    | .text
    | select(type == "string")
    | select(test("^\\s*<(local-command|command-|system-reminder)") | not)
  ] | join("\n");
def human_text:
  select(.type == "user" and (.isMeta // false) == false)
  | .message.content as $c
  | (
      if ($c | type) == "string" then
        if ($c | test("^\\s*<(local-command|system-reminder)")) then empty
        elif ($c | test("<command-name>")) then
          ($c | capture("<command-name>(?<n>.*?)</command-name>"; "s") | .n | trim) as $n
          | (($c | capture("<command-args>(?<a>.*?)</command-args>"; "s")) // {a: ""} | .a | trim) as $a
          | if $a == "" then $n else $n + " " + $a end
        elif ($c | test("^\\s*<command-")) then empty
        else $c end
      elif ($c | type) == "array" then ($c | block_text)
      else empty end
    )
  | trim
  | select(length > 0);
'

adlc_state_dir() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ -n "$common" ] || return 1
  printf '%s/adlc\n' "$common"
}

adlc_toplevel() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

adlc_opted_in() {
  local state top
  state=$(adlc_state_dir "$1") || return 1
  [ -f "$state/enabled" ] && return 0
  top=$(adlc_toplevel "$1") || return 1
  if [ -f "$top/docs/adlc/ADLC_PROCESS.md" ]; then
    mkdir -p "$state" && : >"$state/enabled"
    return 0
  fi
  return 1
}

adlc_disabled() {
  local state
  [ "${ADLC_DISABLE:-}" = "1" ] && return 0
  state=$(adlc_state_dir "$1") || return 1
  [ -f "$state/disabled" ]
}

adlc_human_prompt_count() {
  case "$1" in
    claude) ;;
    *)
      printf '0\n'
      return 1
      ;;
  esac
  jq -Rn "$ADLC_JQ_DEFS"'[inputs | fromjson? | select(type == "object") | human_text] | length' <"$2"
}

ADLC_AWK_STRUCT='
BEGIN {
  split("REQ AC DEC DES IMP TEST PROMPT CYCLE", names, " ")
  for (k in names) keep[names[k]] = 1
  inkey = 0
}
{
  line = $0
  if (inkey) {
    if (line ~ /-----END [A-Z ]*PRIVATE KEY-----/) inkey = 0
    next
  }
  if (line ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) {
    if (mode == "scan") print NR ":private-key"
    else print "[redacted]"
    if (line !~ /-----END [A-Z ]*PRIVATE KEY-----/) inkey = 1
    next
  }
  out = ""
  rest = line
  last = ""
  hit = 0
  while (match(rest, /[A-Z][A-Z0-9]+-[0-9]+/)) {
    s = RSTART
    l = RLENGTH
    tok = substr(rest, s, l)
    prev = (s > 1) ? substr(rest, s - 1, 1) : last
    nxt = substr(rest, s + l, 1)
    pfx = substr(tok, 1, index(tok, "-") - 1)
    plen = length(pfx)
    if (prev !~ /[A-Za-z0-9_]/ && nxt !~ /[A-Za-z0-9_]/ && plen >= 2 && plen <= 10 && !(pfx in keep)) {
      out = out substr(rest, 1, s - 1) "[redacted]"
      hit = 1
    } else {
      out = out substr(rest, 1, s + l - 1)
    }
    rest = substr(rest, s + l)
    last = substr(out, length(out), 1)
  }
  if (mode == "scan") {
    if (hit) print NR ":jira-key"
  } else {
    print out rest
  }
}
'

ADLC_AWK_DENY='
FNR == NR {
  if (length($0) > 0) terms[++n] = tolower($0)
  next
}
{
  if (mode == "scan") {
    low = tolower($0)
    for (i = 1; i <= n; i++) {
      if (index(low, terms[i]) > 0) {
        print FNR ":deny-list"
        break
      }
    }
    next
  }
  line = $0
  for (i = 1; i <= n; i++) {
    out = ""
    while ((pos = index(tolower(line), terms[i])) > 0) {
      out = out substr(line, 1, pos - 1) "[redacted]"
      line = substr(line, pos + length(terms[i]))
    }
    line = out line
  }
  print line
}
'

adlc_patterns() {
  local t
  t=$(printf '\t')
  printf '%s\n' \
    "email${t}[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}${t}[redacted]" \
    "home-path${t}/Users/[^/ ]+${t}[redacted]" \
    "home-path${t}/home/[^/ ]+${t}[redacted]" \
    "github-token${t}ghp_[A-Za-z0-9]{20,}${t}[redacted]" \
    "github-pat${t}github_pat_[A-Za-z0-9_]{20,}${t}[redacted]" \
    "api-key${t}(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}${t}\\1[redacted]" \
    "aws-key${t}AKIA[0-9A-Z]{16}${t}[redacted]" \
    "slack-token${t}xox[abprs]-[A-Za-z0-9-]{10,}${t}[redacted]" \
    "bearer-token${t}Bearer [A-Za-z0-9._~+/=-]{16,}${t}[redacted]" \
    "jwt${t}eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}${t}[redacted]"
}

adlc_scan_file() {
  local file=$1 state=${2:-} class ere repl
  while IFS=$(printf '\t') read -r class ere repl; do
    LC_ALL=C grep -anE -- "$ere" "$file" | cut -d: -f1 | sed "s/\$/:$class/"
  done <<EOF2
$(adlc_patterns)
EOF2
  LC_ALL=C awk -v mode=scan "$ADLC_AWK_STRUCT" "$file"
  if [ -s "$state/deny-list" ]; then
    LC_ALL=C awk -v mode=scan "$ADLC_AWK_DENY" "$state/deny-list" "$file"
  fi
  return 0
}

adlc_redact() {
  local file=$1 state=$2 tmp tmp2 classes class ts id
  local -a args=()
  local ere repl
  classes=$(adlc_scan_file "$file" "$state" | cut -d: -f2 | LC_ALL=C sort -u)
  while IFS=$(printf '\t') read -r _ ere repl; do
    args+=(-e "s#${ere}#${repl}#g")
  done <<EOF2
$(adlc_patterns)
EOF2
  tmp=$(mktemp "${file}.XXXXXX") || return 1
  tmp2=$(mktemp "${file}.XXXXXX") || {
    rm -f "$tmp"
    return 1
  }
  LC_ALL=C sed -E "${args[@]}" "$file" >"$tmp" || {
    rm -f "$tmp" "$tmp2"
    return 1
  }
  LC_ALL=C awk -v mode=redact "$ADLC_AWK_STRUCT" "$tmp" >"$tmp2" || {
    rm -f "$tmp" "$tmp2"
    return 1
  }
  mv "$tmp2" "$tmp"
  if [ -s "$state/deny-list" ]; then
    tmp2=$(mktemp "${file}.XXXXXX") || {
      rm -f "$tmp"
      return 1
    }
    LC_ALL=C awk -v mode=redact "$ADLC_AWK_DENY" "$state/deny-list" "$tmp" >"$tmp2" || {
      rm -f "$tmp" "$tmp2"
      return 1
    }
    mv "$tmp2" "$tmp"
  fi
  mv "$tmp" "$file" || return 1
  if [ -n "$classes" ]; then
    mkdir -p "$state/log" || return 1
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    id=$(basename "$file")
    id=${id%%.*}
    for class in $classes; do
      printf '%s %s %s\n' "$ts" "$id" "$class" >>"$state/log/redactions.log"
    done
  fi
  return 0
}
