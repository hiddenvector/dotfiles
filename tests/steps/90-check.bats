#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  source "$HV_ROOT/setup/lib/docs.sh"
}

@test "docs_current is true for a freshly generated USAGE.md" {
  run hv::docs_current
  [ "$status" -eq 0 ]
}

@test "docs_current is false when a fragment changes" {
  echo "# drift" >> "$HV_ROOT/docs/usage/core.md"
  run hv::docs_current
  local rc="$status"
  git -C "$HV_ROOT" checkout -- docs/usage/core.md
  [ "$rc" -eq 1 ]
}

@test "check warns about untracked personal config with no overlay" {
  mkdir -p "$HV_CONFIG_HOME"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  source "$HV_ROOT/setup/steps/90-check.sh"
  run hv_step_run
  [[ "$stderr$output" == *"overlay"* ]]
}

@test "check does not warn when an overlay is configured" {
  mkdir -p "$HV_CONFIG_HOME" "$HOME/overlay"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  source "$HV_ROOT/setup/steps/90-check.sh"
  run hv_step_run
  [[ "$stderr$output" != *"will not survive"* ]]
}

@test "check does not warn about an empty local.Brewfile" {
  mkdir -p "$HV_CONFIG_HOME"
  : > "$HV_CONFIG_HOME/local.Brewfile"
  source "$HV_ROOT/setup/steps/90-check.sh"
  run hv_step_run
  [[ "$stderr$output" != *"will not survive"* ]]
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/90-check.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
