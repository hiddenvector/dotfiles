#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
  export HV_GIT_CONFIG_HOME="$HOME/.config/git"
  hv_stub scutil 0 "prometheus"
  hv_stub gh 0 "Mark Adams"
  hv_stub ssh-keygen 0 ""
  export HV_YES=1
}

@test "check fails when no identity file exists" {
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check passes when identity and signing key exist" {
  mkdir -p "$HV_GIT_CONFIG_HOME" "$HOME/.ssh"
  printf '[user]\n\temail = a@b.c\n' > "$HV_GIT_CONFIG_HOME/identity"
  touch "$HOME/.ssh/id_ed25519_signing_prometheus"
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "run authenticates gh when not already logged in" {
  hv_stub gh 1 ""
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_run
  hv_assert_called "auth login"
}

@test "run writes a git identity file" {
  source "$HV_ROOT/setup/steps/30-identity.sh"
  hv_step_run
  grep -q "email" "$HV_GIT_CONFIG_HOME/identity"
  grep -q "signingkey" "$HV_GIT_CONFIG_HOME/identity"
}

@test "run names the signing key after the machine" {
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_run
  hv_assert_called "id_ed25519_signing_prometheus"
}

@test "run uploads the signing key to GitHub" {
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_run
  hv_assert_called "ssh-key add"
  hv_assert_called "--type signing"
}

@test "run does not regenerate an existing signing key" {
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/id_ed25519_signing_prometheus"
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_run
  hv_assert_not_called "ssh-keygen"
}

@test "run builds allowed-signers from the team file plus own keys" {
  mkdir -p "$HOME/.ssh"
  echo "ssh-ed25519 AAAAOWN own@example.com" > "$HOME/.ssh/id_ed25519_signing_prometheus.pub"
  source "$HV_ROOT/setup/steps/30-identity.sh"
  hv_step_run
  grep -q "AAAAOWN" "$HV_GIT_CONFIG_HOME/allowed-signers"
  grep -q 'namespaces="git"' "$HV_GIT_CONFIG_HOME/allowed-signers"
}

@test "run regenerating allowed-signers does not duplicate entries" {
  mkdir -p "$HOME/.ssh"
  echo "ssh-ed25519 AAAAOWN own@example.com" > "$HOME/.ssh/id_ed25519_signing_prometheus.pub"
  source "$HV_ROOT/setup/steps/30-identity.sh"
  hv_step_run
  hv_step_run
  run grep -c "AAAAOWN" "$HV_GIT_CONFIG_HOME/allowed-signers"
  [ "$output" = "1" ]
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/30-identity.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
