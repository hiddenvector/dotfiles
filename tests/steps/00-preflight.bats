#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
  hv_stub sw_vers 0 "26.1"
  hv_stub uname 0 "arm64"
  hv_stub xcode-select 0 "/Library/Developer/CommandLineTools"
  hv_stub id 0 "staff admin"
  hv_stub profiles 0 "MDM enrollment: No"
}

@test "check passes on a supported machine" {
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "check fails when Command Line Tools are absent" {
  hv_stub xcode-select 1 ""
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "run refuses an unsupported macOS version" {
  hv_stub sw_vers 0 "13.6"
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_run
  [ "$status" -ne 0 ]
  [[ "$stderr$output" == *"macOS 14"* ]]
}

@test "run refuses a non-arm64 machine" {
  hv_stub uname 0 "x86_64"
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_run
  [ "$status" -ne 0 ]
  [[ "$stderr$output" == *"arm64"* ]]
}

@test "run installs Command Line Tools when missing" {
  hv_stub xcode-select 1 ""
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_run
  hv_assert_called "xcode-select --install"
}

@test "run warns but does not fail for a non-admin account" {
  hv_stub id 0 "staff everyone"
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  [[ "$stderr$output" == *"admin"* ]]
}

@test "step scope is system" {
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  [ "$HV_STEP_SCOPE" = "system" ]
}
