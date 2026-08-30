#!/usr/bin/env bats

load ../helper

SKILL="$HV_ROOT/claude/skills/hv-toolbelt/SKILL.md"

@test "skill has frontmatter with name and description" {
  head -1 "$SKILL" | grep -q -- '---'
  grep -q '^name: hv-toolbelt' "$SKILL"
  grep -q '^description: ' "$SKILL"
}

@test "skill lists every interactive helper as unsafe" {
  for c in ff ffa fif gcof glogf j zi; do
    grep -q "$c" "$SKILL"
  done
  grep -qi "hang" "$SKILL"
}

@test "skill lists the bin helpers as safe" {
  grep -q "gprune" "$SKILL"
  grep -q "gbd" "$SKILL"
}

@test "skill points at the generated reference rather than duplicating it" {
  grep -q "docs/USAGE.md" "$SKILL"
}

@test "skill is short enough to stay cheap" {
  run wc -l < "$SKILL"
  [ "$output" -lt 120 ]
}

@test "START-HERE lists at most ten commands" {
  run grep -c '^| `' "$HV_ROOT/docs/START-HERE.md"
  [ "$output" -le 10 ]
}

@test "ONBOARDING covers the per-repo setup that hv clone does not automate" {
  grep -q "pre-commit install" "$HV_ROOT/docs/ONBOARDING.md"
  grep -q ".env.local" "$HV_ROOT/docs/ONBOARDING.md"
  grep -q "gh auth login" "$HV_ROOT/docs/ONBOARDING.md"
}
