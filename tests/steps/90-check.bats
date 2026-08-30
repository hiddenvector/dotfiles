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
  # HV_ROOT points at the real checkout -- hv_setup_sandbox only sandboxes
  # $HOME and $PATH, not the repo tree -- so this test mutates the real
  # docs/usage/core.md. Restore its actual prior bytes rather than
  # `git checkout --`, which restores from the index: an edit made to this
  # file but not yet staged would otherwise be silently destroyed by this
  # test. Restore happens before the assertion, so even a failing
  # assertion here cannot leave the file mutated.
  local frag="$HV_ROOT/docs/usage/core.md"
  local backup="$BATS_TEST_TMPDIR/core.md.bak"
  cp "$frag" "$backup"
  printf '\n# drift\n' >> "$frag"
  run hv::docs_current
  local rc="$status"
  cp "$backup" "$frag"
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
