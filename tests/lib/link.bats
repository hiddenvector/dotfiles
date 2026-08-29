#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/link.sh"
  SRC="$BATS_TEST_TMPDIR/src"
  echo "content" > "$SRC"
}

@test "hv::link creates a symlink" {
  hv::link "$SRC" "$HOME/.zshrc"
  [ -L "$HOME/.zshrc" ]
  [ "$(readlink "$HOME/.zshrc")" = "$SRC" ]
}

@test "hv::link creates missing parent directories" {
  hv::link "$SRC" "$HOME/.config/deep/nested/file"
  [ -L "$HOME/.config/deep/nested/file" ]
}

@test "hv::link is idempotent" {
  hv::link "$SRC" "$HOME/.zshrc"
  hv::link "$SRC" "$HOME/.zshrc"
  [ "$(readlink "$HOME/.zshrc")" = "$SRC" ]
}

@test "hv::link backs up a pre-existing regular file instead of failing" {
  echo "hand written" > "$HOME/.zshrc"
  run hv::link "$SRC" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.zshrc" ]
  ls "$HOME"/.zshrc.bak.* >/dev/null
  grep -q "hand written" "$HOME"/.zshrc.bak.*
}

@test "hv::link retargets a symlink pointing somewhere else" {
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$HOME/.zshrc"
  hv::link "$SRC" "$HOME/.zshrc"
  [ "$(readlink "$HOME/.zshrc")" = "$SRC" ]
}

@test "hv::linked reports true only for a correct link" {
  hv::link "$SRC" "$HOME/.zshrc"
  run hv::linked "$SRC" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  run hv::linked "$BATS_TEST_TMPDIR/other" "$HOME/.zshrc"
  [ "$status" -eq 1 ]
}

@test "hv::linked reports false for a missing destination" {
  run hv::linked "$SRC" "$HOME/.nope"
  [ "$status" -eq 1 ]
}

@test "hv::link under dry run mutates nothing" {
  HV_DRY_RUN=1
  hv::link "$SRC" "$HOME/.zshrc"
  [ ! -e "$HOME/.zshrc" ]
}
