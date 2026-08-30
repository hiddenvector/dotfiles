#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
  export HV_BREW_PREFIX="$BATS_TEST_TMPDIR/homebrew"
  mkdir -p "$HV_BREW_PREFIX/bin"
  hv_stub brew 0 ""
  hv_stub sudo 0 ""
  hv_stub id 0 "staff admin"
  hv_stub curl 0 ""
  export HV_YES=1
}

@test "check fails when brew is not installed" {
  rm -rf "$HV_BREW_PREFIX"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check passes when brew exists and the core bundle is satisfied" {
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" "brew" 0
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
  hv_assert_called "bundle check"
}

@test "check fails when the core bundle is unsatisfied" {
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" "brew" 1
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "run installs Homebrew when absent" {
  rm -rf "$HV_BREW_PREFIX"
  hv_stub curl 0 "echo installed-homebrew"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  hv_assert_called "curl"
}

@test "run installs the core bundle" {
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" "brew" 0
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  hv_assert_called "bundle --file"
}

@test "run offers the admin-group share when the prefix is not writable" {
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" "brew" 0
  chmod -w "$HV_BREW_PREFIX"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  chmod +w "$HV_BREW_PREFIX"
  [[ "$stderr$output" == *"another account"* ]]
}

@test "run states the tradeoff before sharing write access" {
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" "brew" 0
  chmod -w "$HV_BREW_PREFIX"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  chmod +w "$HV_BREW_PREFIX"
  [[ "$stderr$output" == *"any admin user"* ]]
}

@test "run does not chgrp when the prefix is already writable" {
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" "brew" 0
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  hv_assert_not_called "chgrp"
}

@test "core Brewfile contains the tools every module depends on" {
  for f in git git-delta gh starship fzf ripgrep bat eza zoxide; do
    grep -q "\"$f\"" "$HV_ROOT/brew/core.Brewfile"
  done
}

@test "run warns when bundle installation fails but returns 0" {
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" "brew" 1
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  # `[ ]`/`case`, not `[[ ]]`, for the non-final check: bash 3.2's `set -e`
  # does not reliably abort on a failing `[[ ]]` unless it is the function's
  # last statement.
  case "$stderr$output" in
    *"installation failed"*) : ;;
    *) return 1 ;;
  esac
  [[ "$stderr$output" != *"✓ core packages"* ]]
}

@test "dry run does not install Homebrew or packages" {
  rm -rf "$HV_BREW_PREFIX"
  export HV_DRY_RUN=1
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  hv_assert_not_called "curl"
}
