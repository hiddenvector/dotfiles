#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
  export HV_PAM_FILE="$BATS_TEST_TMPDIR/sudo_local"
  hv_stub bioutil 0 ""
  hv_stub profiles 0 "MDM enrollment: No"
  hv_stub sudo 0 ""
}

@test "check fails when the pam file is absent" {
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check passes when pam_tid is configured" {
  echo "auth       sufficient     pam_tid.so" > "$HV_PAM_FILE"
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "run writes the pam config via sudo tee" {
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  hv_assert_called "tee"
}

@test "run warns and skips when there is no Touch ID sensor" {
  hv_stub bioutil 1 ""
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  # `[ ]`/`case`, not `[[ ]]`, for the non-final check: bash 3.2's `set -e`
  # does not reliably abort on a failing `[[ ]]` unless it is the function's
  # last statement.
  case "$stderr$output" in
    *"no Touch ID sensor"*) : ;;
    *) return 1 ;;
  esac
  hv_assert_not_called "tee"
}

@test "run degrades to a warning when the pam write is blocked" {
  hv_stub sudo 1 ""
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  [[ "$stderr$output" == *"blocked"* ]]
}

@test "run is idempotent" {
  echo "auth       sufficient     pam_tid.so" > "$HV_PAM_FILE"
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  hv_assert_not_called "tee"
}

@test "run mentions the ssh limitation" {
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  [[ "$stderr$output" == *"SSH"* ]]
}

@test "step scope is system" {
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  [ "$HV_STEP_SCOPE" = "system" ]
}

@test "dry run does not write the pam file and does not claim success" {
  HV_DRY_RUN=1
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  hv_assert_not_called "sudo"
  # `[ ]`/`case`, not `[[ ]]`, for the non-final check: bash 3.2's `set -e`
  # does not reliably abort on a failing `[[ ]]` unless it is the function's
  # last statement.
  case "$stderr$output" in
    *written*) return 1 ;;
  esac
  [[ "$stderr$output" == *"would"* ]]
}
