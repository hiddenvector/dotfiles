#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  hv_stub defaults 0 ""
  hv_stub killall 0 ""
}

@test "run writes trackpad, keyboard, dock and finder defaults" {
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_called "TrackpadThreeFingerDrag"
  hv_assert_called "KeyRepeat"
  hv_assert_called "com.apple.dock autohide"
  hv_assert_called "ShowPathbar"
}

@test "run does not touch Touch ID — that is step 05" {
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_not_called "pam_tid"
  hv_assert_not_called "sudo_local"
}

@test "run applies the overlay's macos.sh when present" {
  mkdir -p "$HOME/overlay"
  echo 'echo overlay-macos-ran' > "$HOME/overlay/macos.sh"
  chmod +x "$HOME/overlay/macos.sh"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  [[ "$output" == *"overlay-macos-ran"* ]]
}

@test "a failing overlay macos.sh warns and does not claim success" {
  mkdir -p "$HOME/overlay"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$HOME/overlay/macos.sh"
  chmod +x "$HOME/overlay/macos.sh"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  case "$stderr$output" in *"macos.sh failed"*) : ;; *) return 1 ;; esac
  case "$output" in *"✓ overlay macos.sh"*) return 1 ;; esac
}

@test "run warns that three-finger drag needs a logout" {
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  [[ "$stderr$output" == *"logout"* ]]
}

@test "run under dry run writes nothing" {
  HV_DRY_RUN=1
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_not_called "TrackpadThreeFingerDrag"
  [[ ! "$output" =~ "trackpad, keyboard, dock, finder" ]]
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/60-macos.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
