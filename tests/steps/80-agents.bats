#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/link.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  hv_stub claude 0 ""
}

@test "run links the house rules" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  [ -L "$HOME/.claude/hv/house-rules.md" ]
}

@test "run creates CLAUDE.md with the import when none exists" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  grep -q "@~/.claude/hv/house-rules.md" "$HOME/.claude/CLAUDE.md"
}

@test "run preserves an existing CLAUDE.md" {
  mkdir -p "$HOME/.claude"
  echo "# My own notes" > "$HOME/.claude/CLAUDE.md"
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  grep -q "My own notes" "$HOME/.claude/CLAUDE.md"
  grep -q "@~/.claude/hv/house-rules.md" "$HOME/.claude/CLAUDE.md"
}

@test "run does not add the import twice" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  hv_step_run
  run grep -c "house-rules.md" "$HOME/.claude/CLAUDE.md"
  [ "$output" = "1" ]
}

@test "run links the toolbelt skill" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  [ -L "$HOME/.claude/skills/hv-toolbelt" ]
}

@test "run installs the superpowers plugin" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  run hv_step_run
  hv_assert_called "superpowers"
}

@test "house rules do not inline the tool reference" {
  # The reference belongs in the lazily-loaded skill, not in every session.
  run wc -l < "$HV_ROOT/claude/CLAUDE.md"
  [ "$output" -lt 60 ]
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}

@test "dry run writes nothing and claims nothing" {
  export HV_DRY_RUN=1
  # Pre-create the directory so a missing dry-run guard would actually
  # succeed at writing (and falsely claim it) rather than merely failing
  # for the incidental reason that hv::run also no-ops the mkdir above.
  mkdir -p "$HOME/.claude"
  source "$HV_ROOT/setup/steps/80-agents.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/CLAUDE.md" ]
  [ ! -e "$HOME/.claude/hv/house-rules.md" ]
  [ ! -e "$HOME/.claude/skills/hv-toolbelt" ]
  case "$output" in
    *"✓"*) false ;;
    *) true ;;
  esac
  hv_assert_no_refusals
}

@test "run does not claim success when the CLAUDE.md write fails" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  mkdir -p "$HOME/.claude"
  # A directory where the file should be makes the write fail without
  # touching the real filesystem outside the sandbox.
  mkdir -p "$HOME/.claude/CLAUDE.md"
  run hv_step_run
  case "$output" in
    *"created ~/.claude/CLAUDE.md"*|*"added house rules import"*) false ;;
  esac
  case "$output" in
    *"could not create ~/.claude/CLAUDE.md"*) true ;;
    *) false ;;
  esac
}

@test "an existing settings.json is never replaced" {
  mkdir -p "$HOME/.claude"
  printf '{"model":"opus","statusLine":{"type":"command"}}' > "$HOME/.claude/settings.json"
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  # The user's own file survives byte-for-byte: not moved, not merged,
  # not backed up-and-replaced.
  [ "$(cat "$HOME/.claude/settings.json")" = '{"model":"opus","statusLine":{"type":"command"}}' ]
  [ ! -L "$HOME/.claude/settings.json" ]
  [ -L "$HOME/.claude/settings.hv.json" ]
}

@test "settings.json is installed when none exists" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  [ -L "$HOME/.claude/settings.json" ]
}

@test "check reports drift when the toolbelt link is missing" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  rm -f "$HOME/.claude/skills/hv-toolbelt"
  run hv_step_check
  [ "$status" -eq 1 ]
}
