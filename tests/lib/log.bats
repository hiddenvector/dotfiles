#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
}

@test "hv::ok writes a check mark to stdout" {
  run hv::ok "linked"
  [ "$status" -eq 0 ]
  # `[ ]`/`case`, not `[[ ]]`, for the non-final check: bash 3.2's `set -e`
  # does not reliably abort on a failing `[[ ]]` unless it is the function's
  # last statement.
  case "$output" in
    *"✓"*) : ;;
    *) return 1 ;;
  esac
  [[ "$output" == *"linked"* ]]
}

@test "hv::warn writes to stderr, not stdout" {
  run --separate-stderr hv::warn "no sensor"
  [ "$output" = "" ]
  [[ "$stderr" == *"no sensor"* ]]
}

@test "hv::run executes the command when not dry running" {
  HV_DRY_RUN=0
  hv::run touch "$HOME/made-it"
  [ -f "$HOME/made-it" ]
}

@test "hv::run mutates nothing when dry running" {
  HV_DRY_RUN=1
  run hv::run touch "$HOME/made-it"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/made-it" ]
  [[ "$output" == *"would run"* ]]
}

@test "hv::die exits nonzero" {
  run hv::die "boom"
  [ "$status" -eq 1 ]
}
