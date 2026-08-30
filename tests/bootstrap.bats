#!/usr/bin/env bats

load helper

@test "bootstrap duplicates no converge step" {
  ! grep -qE 'pam_tid|brew bundle|scutil --set' "$HV_ROOT/bootstrap"
}

@test "bootstrap execs hv setup" {
  grep -q 'exec .*hv.* setup' "$HV_ROOT/bootstrap"
}

@test "bootstrap clones to the conventional path" {
  grep -q 'Developer/github.com/hiddenvector/dotfiles' "$HV_ROOT/bootstrap"
}

@test "bootstrap is idempotent when the clone already exists" {
  grep -q 'git -C .* pull' "$HV_ROOT/bootstrap"
}

@test "bootstrap passes shellcheck" {
  run shellcheck "$HV_ROOT/bootstrap"
  [ "$status" -eq 0 ]
}

@test "README documents reading bootstrap before running it" {
  grep -qi "read it first" "$HV_ROOT/README.md"
}
