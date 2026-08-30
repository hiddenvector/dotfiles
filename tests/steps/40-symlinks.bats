#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/link.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  export HV_GIT_CONFIG_HOME="$HOME/.config/git"
}

@test "tracked gitconfig contains no identity" {
  ! grep -qE '^\s*(name|email|signingkey)\s*=' "$HV_ROOT/git/gitconfig"
}

@test "tracked gitconfig includes the identity file" {
  grep -q 'path = ~/.config/git/identity' "$HV_ROOT/git/gitconfig"
}

@test "tracked gitconfig conditionally includes the HV identity" {
  grep -q 'includeIf "gitdir:~/Developer/github.com/hiddenvector/"' "$HV_ROOT/git/gitconfig"
}

@test "tracked gitconfig includes the generated local file last" {
  local last
  last="$(grep -n 'path = ~/.config/git/' "$HV_ROOT/git/gitconfig" | tail -1)"
  case "$last" in
    *local*) : ;;
    *) return 1 ;;
  esac
}

@test "run links the core dotfiles" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  [ -L "$HOME/.gitconfig" ]
  [ -L "$HOME/.gitignore_global" ]
  [ -L "$HOME/.zshrc" ]
  [ -L "$HOME/.zprofile" ]
  [ -L "$HOME/.config/starship.toml" ]
}

@test "run links every zshrc.d fragment" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  [ -L "$HOME/.zshrc.d/git.zsh" ]
  [ -L "$HOME/.zshrc.d/fzf.zsh" ]
}

@test "run links bin executables onto PATH" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  [ -L "$HOME/.local/bin/hv" ]
}

@test "run creates the secrets stub with 0600 permissions" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  [ -f "$HOME/.secrets" ]
  [ "$(stat -f '%Lp' "$HOME/.secrets")" = "600" ]
}

@test "run points the generated git local file at the overlay" {
  mkdir -p "$HOME/overlay/git"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  hv::config_load
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  grep -q "$HOME/overlay/git/config" "$HV_GIT_CONFIG_HOME/local"
}

@test "run writes an empty git local file when there is no overlay" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  [ -f "$HV_GIT_CONFIG_HOME/local" ]
  ! grep -q "overlay" "$HV_GIT_CONFIG_HOME/local"
}

@test "run is idempotent" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  run hv_step_run
  [ "$status" -eq 0 ]
  [ -L "$HOME/.zshrc" ]
}

@test "check fails before running and passes after" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
  hv_step_run
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "run makes no changes under dry-run" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  export HV_DRY_RUN=1
  run hv_step_run
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.gitconfig" ]
  [ ! -e "$HOME/.zshrc" ]
  [ ! -e "$HOME/.secrets" ]
  [ ! -e "$HV_GIT_CONFIG_HOME/local" ]
  run hv_step_check
  [ "$status" -eq 1 ]
}

# AMENDMENT: the brief's appended .zshrc block reads ${HV_OVERLAY:-} but
# nothing ever sets HV_OVERLAY in an interactive shell — it lives in
# ~/.config/hv/config, which the shell never reads on its own. Without
# sourcing that file first, an overlay's zshrc.d fragments would silently
# never load. This test proves the fix: a real zsh process, given only the
# generated config file (no HV_OVERLAY in its environment), still sources an
# overlay fragment placed on disk.
@test ".zshrc sources an overlay's zshrc.d fragments when HV_OVERLAY is set only in the config file" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run

  mkdir -p "$HOME/overlay/zshrc.d"
  cat > "$HOME/overlay/zshrc.d/marker.zsh" <<'FRAG'
echo "OVERLAY_FRAGMENT_LOADED"
FRAG

  mkdir -p "$HV_CONFIG_HOME"
  printf 'export HV_OVERLAY="%s"\n' "$HOME/overlay" > "$HOME/.config/hv/config"

  # Minimal PATH: keep the zshrc's real logic under test without depending
  # on whatever dev tools (starship, fzf, eza, zoxide, bat) happen to be
  # installed on the machine running this suite. HV_OVERLAY is deliberately
  # NOT exported here — the whole point is that .zshrc must pick it up from
  # the config file on disk, not from the environment.
  run env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    zsh -c 'source "$HOME/.zshrc"' < /dev/null
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q "OVERLAY_FRAGMENT_LOADED"
}

@test "run materializes a stale local.zsh symlink from another dotfiles repo" {
  mkdir -p "$HOME/other-dotfiles/zsh" "$HOME/.zshrc.d"
  printf 'export FOO=bar\n' > "$HOME/other-dotfiles/zsh/local.zsh"
  ln -sfn "$HOME/other-dotfiles/zsh/local.zsh" "$HOME/.zshrc.d/local.zsh"

  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  run hv_step_run
  [ "$status" -eq 0 ]

  [ ! -L "$HOME/.zshrc.d/local.zsh" ]
  [ -f "$HOME/.zshrc.d/local.zsh" ]
  grep -q "FOO=bar" "$HOME/.zshrc.d/local.zsh"
  case "$output" in
    *"was a symlink into"*) : ;;
    *) return 1 ;;
  esac
}

@test "run replaces a dangling local.zsh symlink with the standard stub" {
  mkdir -p "$HOME/.zshrc.d"
  ln -sfn "$HOME/gone-repo/zsh/local.zsh" "$HOME/.zshrc.d/local.zsh"

  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  run hv_step_run
  [ "$status" -eq 0 ]

  [ ! -L "$HOME/.zshrc.d/local.zsh" ]
  [ -f "$HOME/.zshrc.d/local.zsh" ]
  grep -q "source ~/.secrets" "$HOME/.zshrc.d/local.zsh"
  case "$output" in
    *"was a dangling symlink"*) : ;;
    *) return 1 ;;
  esac
}

@test "dry run leaves a stale local.zsh symlink untouched and claims nothing" {
  mkdir -p "$HOME/other-dotfiles/zsh" "$HOME/.zshrc.d"
  printf 'export FOO=bar\n' > "$HOME/other-dotfiles/zsh/local.zsh"
  ln -sfn "$HOME/other-dotfiles/zsh/local.zsh" "$HOME/.zshrc.d/local.zsh"

  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  export HV_DRY_RUN=1
  run hv_step_run
  [ "$status" -eq 0 ]

  [ -L "$HOME/.zshrc.d/local.zsh" ]
  [ "$(readlink "$HOME/.zshrc.d/local.zsh")" = "$HOME/other-dotfiles/zsh/local.zsh" ]
  case "$output" in
    *"would copy"*) : ;;
    *) return 1 ;;
  esac
}

@test "dry run leaves a dangling local.zsh symlink untouched and claims nothing" {
  mkdir -p "$HOME/.zshrc.d"
  ln -sfn "$HOME/gone-repo/zsh/local.zsh" "$HOME/.zshrc.d/local.zsh"

  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  export HV_DRY_RUN=1
  run hv_step_run
  [ "$status" -eq 0 ]

  [ -L "$HOME/.zshrc.d/local.zsh" ]
  [ ! -e "$HOME/.zshrc.d/local.zsh" ]
  case "$output" in
    *"would replace dangling"*) : ;;
    *) return 1 ;;
  esac
}

@test "run does not touch local.zsh once it is a real file" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  printf 'export ALREADY=here\n' >> "$HOME/.zshrc.d/local.zsh"
  run hv_step_run
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.zshrc.d/local.zsh" ]
  grep -q "ALREADY=here" "$HOME/.zshrc.d/local.zsh"
}

@test ".zshrc does not error when no overlay is configured" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  run env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    zsh -c 'source "$HOME/.zshrc"' < /dev/null
  [ "$status" -eq 0 ]
}
