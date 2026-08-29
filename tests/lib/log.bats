#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
}

@test "hv::ok writes a check mark to stdout" {
  run hv::ok "linked"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
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
