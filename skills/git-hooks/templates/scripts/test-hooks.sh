#!/bin/sh
ROOT=$(cd "$(dirname "$0")/.." && pwd) || exit 1
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' INT TERM

passed=0
total=0
ZERO=0000000000000000000000000000000000000000

fail_setup() {
  echo "setup failed: $1" >&2
  exit 1
}

check() {
  name=$1
  expect=$2
  text=$3
  shift 3
  total=$((total + 1))
  "$@" >"$TMP/out" 2>"$TMP/err"
  code=$?
  ok=1
  if [ "$expect" = accepted ]; then
    [ "$code" -eq 0 ] || ok=0
  else
    [ "$code" -ne 0 ] || ok=0
    grep -qF -- "$text" "$TMP/err" || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    passed=$((passed + 1))
    echo "PASS $name"
  else
    echo "FAIL $name (exit $code, expected $expect${text:+ with \"$text\"})"
    sed 's/^/  | /' "$TMP/err" | tail -15
  fi
}

reset_tree() {
  git -C "$1" reset -q --hard
  git -C "$1" clean -fdq
}

stage_file() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add "$2"
}

commit_valid() {
  git -C "$1" commit -q -m "docs: add $2" -m "Why: exercise the hooks." -m "What: add a note."
}

push_stdin() {
  printf 'refs/heads/%s %s refs/heads/%s %s\n' "$2" "$(git -C "$1" rev-parse HEAD)" "$2" "$ZERO" |
    (cd "$1" && .githooks/pre-push origin url)
}

git clone -q "$ROOT" "$TMP/repo" || fail_setup clone
git -C "$TMP/repo" checkout -q -B main || fail_setup checkout
git -C "$TMP/repo" config user.name tester
git -C "$TMP/repo" config user.email tester@example.com
git -C "$TMP/repo" config commit.gpgsign false
for item in .githooks scripts mise.toml mise.lock; do
  [ -e "$ROOT/$item" ] && cp -R "$ROOT/$item" "$TMP/repo/"
done
git -C "$TMP/repo" add -A
git -C "$TMP/repo" diff --cached --quiet ||
  git -C "$TMP/repo" -c core.hooksPath=/dev/null commit -q -m "chore: sync hooks under test" ||
  fail_setup sync
git -C "$TMP/repo" config core.hooksPath .githooks
cp "$ROOT/local.properties" "$TMP/repo/" || fail_setup properties
git -C "$TMP/repo" checkout -q -b base || fail_setup base

WT="$TMP/wt"
WTMAIN="$TMP/wtmain"
WTSPACE="$TMP/wt space"
git -C "$TMP/repo" worktree add -q "$WT" -b feat/x main || fail_setup worktree
git -C "$TMP/repo" worktree add -q "$WTMAIN" main || fail_setup worktree-main
git -C "$TMP/repo" worktree add -q "$WTSPACE" -b feat/space main || fail_setup worktree-space
for dir in "$WT" "$WTMAIN" "$WTSPACE"; do
  cp "$ROOT/local.properties" "$dir/" || fail_setup properties
done

stage_file "$TMP/repo" notes/a.txt a
check "(a) commit in the main checkout is refused" refused "use a worktree" commit_valid "$TMP/repo" a
reset_tree "$TMP/repo"

stage_file "$WTMAIN" notes/b.txt b
check "(b) commit on main in a worktree is refused" refused "refusing to commit on main" commit_valid "$WTMAIN" b
reset_tree "$WTMAIN"

stage_file "$WT" notes/c.txt c
check "(c) bad commit message is refused" refused "type must be one of" git -C "$WT" commit -q -m bad
reset_tree "$WT"

stage_file "$WT" domain/src/main/kotlin/io/github/eastwoodno1/supersnake/domain/Tmp.kt "// x"
check "(d) comment in a Kotlin file is refused" refused "comment not allowed" commit_valid "$WT" d
reset_tree "$WT"

stage_file "$WT" notes/e.txt e
check "(e) valid commit in a worktree is accepted" accepted "" commit_valid "$WT" e

git -C "$TMP/repo" branch -q other main
git -C "$TMP/repo" worktree add -q "$TMP/wtother" other || fail_setup worktree-other
stage_file "$TMP/wtother" notes/other.txt other
git -C "$TMP/wtother" -c core.hooksPath=/dev/null commit -q -m "chore: advance other"
rebase_replay() {
  git -C "$WT" rebase -q -x 'git commit --amend --no-edit' --onto other HEAD~1
}
check "(f) rebase replaying a valid commit is accepted" accepted "" rebase_replay

stage_file "$WTSPACE" notes/g.txt g
check "(g) worktree path with a space is accepted" accepted "" commit_valid "$WTSPACE" g

push_failing_test() {
  push_stdin "$WT" main >/dev/null 2>"$TMP/main.err" && return 0
  grep -qF "refusing to push to main" "$TMP/main.err" || return 0
  push_stdin "$WT" feat/x
}
mkdir -p "$WT/domain/src/test/kotlin/io/github/eastwoodno1/supersnake/domain"
cat >"$WT/domain/src/test/kotlin/io/github/eastwoodno1/supersnake/domain/FailingTest.kt" <<'KT'
package io.github.eastwoodno1.supersnake.domain

import kotlin.test.Test
import kotlin.test.assertEquals

class FailingTest {
    @Test
    fun fails() {
        assertEquals(1, 2)
    }
}
KT
check "(h) pre-push refuses main and a failing unit test" refused "FailingTest" push_failing_test
rm -f "$WT/domain/src/test/kotlin/io/github/eastwoodno1/supersnake/domain/FailingTest.kt"

mkdir -p "$WT/.github/workflows"
cat >"$WT/.github/workflows/bad.yml" <<'YML'
name: bad
on: push
permissions: {}
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
YML
check "(i) pre-push with an unpinned action is refused" refused "unpinned-uses" push_stdin "$WT" feat/x
rm -rf "$WT/.github"

echo "$passed/$total passed"
[ "$total" -eq 9 ] && [ "$passed" -eq "$total" ]
