is_main_checkout() {
  [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ]
}

on_main_branch() {
  [ "$(git symbolic-ref -q --short HEAD)" = main ]
}

find_mise() {
  if command -v mise >/dev/null 2>&1; then
    MISE=$(command -v mise)
  elif [ -x "$HOME/.local/bin/mise" ]; then
    MISE="$HOME/.local/bin/mise"
  else
    echo "mise not found on PATH or at $HOME/.local/bin/mise: install it with 'curl -fsSL https://mise.run | sh'" >&2
    return 1
  fi
}

enter_repo() {
  cd "$(git rev-parse --show-toplevel)" || exit 1
}
