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

# A years-old ~/.gitconfig or ~/.zshrc getting silently renamed behind one
# easy-to-miss warning line is exactly what an earlier ruling refused to let
# happen to settings.json. This asserts the backup gets the loud treatment:
# the exact backup path named, and explicit merge-by-hand guidance -- not
# just proof that a backup exists on disk.
@test "hv::link warns loudly and names the exact backup path" {
  echo "hand written" > "$HOME/.gitconfig"
  run hv::link "$SRC" "$HOME/.gitconfig"
  [ "$status" -eq 0 ]
  local backup
  backup="$(ls "$HOME"/.gitconfig.bak.*)"
  case "$output" in
    *"$backup"*) : ;;
    *) return 1 ;;
  esac
  case "$output" in
    *"merge"*) : ;;
    *) return 1 ;;
  esac
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

@test "hv::link prints no success line under dry run" {
  HV_DRY_RUN=1
  run hv::link "$SRC" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q "linked $HOME/.zshrc"
}
