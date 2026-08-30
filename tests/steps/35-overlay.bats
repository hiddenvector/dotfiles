#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
  hv_stub gh 0 "someuser"
  hv_stub git 0 ""
  export HV_YES=1
}

@test "check passes when an overlay is configured and cloned" {
  mkdir -p "$HOME/overlay"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "check passes when the user explicitly declined" {
  hv::config_set HV_OVERLAY "none"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "check fails when configured but the clone is missing" {
  hv::config_set HV_OVERLAY "$HOME/gone"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check fails when nothing is configured" {
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "run clones a configured overlay that is missing locally" {
  hv::config_set HV_OVERLAY "$HOME/overlay"
  hv::config_set HV_OVERLAY_URL "https://github.com/someuser/dotfiles"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run
  hv_assert_called "clone"
}

@test "run offers an existing GitHub repo as the default" {
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run
  [[ "$output" == *"someuser/dotfiles"* ]]
}

@test "run never creates a repo under --yes alone" {
  hv_stub gh 1 ""
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run < /dev/null
  hv_assert_not_called "repo create"
}

@test "run creates a private repo by default when confirmed" {
  hv_stub gh 1 ""
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  # Three distinct answers: "y" confirms creation, then two blank lines accept
  # the repo-name and visibility defaults. `yes y` would answer every prompt
  # with "y", including visibility, producing "--y" instead of "--private" --
  # defeating the point of this test, which is that private is the default.
  # HV_YES is forced off here so hv::ask actually reads these answers instead
  # of short-circuiting to its default (as the outer HV_YES=1 would).
  run bash -c "printf 'y\n\n\n' | { export HV_YES=0; source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/config.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; source '$HV_ROOT/setup/steps/35-overlay.sh'; hv_step_run; }"
  hv_assert_called "--private"
}

@test "run scaffolds the overlay contract directories" {
  export HV_OVERLAY_DIR="$HOME/overlay"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  hv::_scaffold_overlay "$HV_OVERLAY_DIR"
  [ -f "$HV_OVERLAY_DIR/brew/personal.Brewfile" ]
  [ -f "$HV_OVERLAY_DIR/zshrc.d/personal.zsh" ]
  [ -f "$HV_OVERLAY_DIR/git/config" ]
  [ -f "$HV_OVERLAY_DIR/README.md" ]
}

@test "run migrates existing local config into a new overlay" {
  mkdir -p "$HV_CONFIG_HOME" "$HOME/.zshrc.d" "$HOME/overlay"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  hv::_scaffold_overlay "$HOME/overlay"
  hv::_migrate_local "$HOME/overlay"
  grep -q "chatgpt" "$HOME/overlay/brew/personal.Brewfile"
  [ ! -f "$HV_CONFIG_HOME/local.Brewfile" ]
}

@test "the scaffolded README explains the contract" {
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  hv::_scaffold_overlay "$HOME/overlay"
  grep -q "brew/" "$HOME/overlay/README.md"
  grep -q "zshrc.d/" "$HOME/overlay/README.md"
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
