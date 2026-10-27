#!/usr/bin/env bash

fail() {
  printf '%s\n' "$*" >&2
  return 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "expected [$1] got [$2]${3:+ ($3)}"
}

assert_file_eq() {
  diff "$1" "$2" >&2 || fail "files differ: $1 $2"
}

assert_le() {
  [ "$2" -le "$1" ] || fail "expected $2 <= $1${3:+ ($3)}"
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "expected [$1] to contain [$2]" ;;
  esac
}

assert_status() {
  [ "$1" -eq "$2" ] || fail "expected status $1 got $2${3:+ ($3)}"
}
