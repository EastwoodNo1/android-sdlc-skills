#!/usr/bin/env bash

new_repo() {
  git init -q "$1"
  git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
}

rep() {
  local out="" i=0
  while [ "$i" -lt "$2" ]; do
    out="$out$1"
    i=$((i + 1))
  done
  printf '%s' "$out"
}
