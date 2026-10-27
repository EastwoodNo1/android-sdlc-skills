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

adlc_redact() {
  local file=$1 state=$2 tmp
  tmp=$(mktemp "${file}.XXXXXX") || return 1
  LC_ALL=C sed -E \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[redacted]/g' \
    -e 's#/Users/[^/ ]+#[redacted]#g' \
    -e 's#/home/[^/ ]+#[redacted]#g' \
    "$file" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if [ -s "$state/deny-list" ]; then
    local tmp2
    tmp2=$(mktemp "${file}.XXXXXX") || {
      rm -f "$tmp"
      return 1
    }
    LC_ALL=C awk '
      FNR == NR {
        if (length($0) > 0) terms[++n] = tolower($0)
        next
      }
      {
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
    ' "$state/deny-list" "$tmp" >"$tmp2" || {
      rm -f "$tmp" "$tmp2"
      return 1
    }
    mv "$tmp2" "$tmp"
  fi
  mv "$tmp" "$file"
}
