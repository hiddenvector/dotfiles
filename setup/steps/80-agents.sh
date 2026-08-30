#!/usr/bin/env bash
# House rules compose with whatever the person already has: the repo's rules
# are linked and referenced by one @import line, prepended, never written
# over theirs.

export HV_STEP_NAME="agents"
export HV_STEP_SCOPE="user"

HV_CLAUDE_HOME="${HV_CLAUDE_HOME:-$HOME/.claude}"
HV_IMPORT_LINE="@~/.claude/hv/house-rules.md"

hv_step_check() {
  hv::linked "$HV_ROOT/claude/CLAUDE.md" "$HV_CLAUDE_HOME/hv/house-rules.md" \
    && grep -q "house-rules.md" "$HV_CLAUDE_HOME/CLAUDE.md" 2>/dev/null
}

hv_step_run() {
  hv::step 80 "agents"

  hv::link "$HV_ROOT/claude/CLAUDE.md" "$HV_CLAUDE_HOME/hv/house-rules.md"
  hv::link "$HV_ROOT/claude/settings.json" "$HV_CLAUDE_HOME/settings.json"

  # The hv-toolbelt skill ships in a later step. ln -sfn happily creates a
  # dangling symlink for a target that does not exist yet, and it resolves
  # itself the moment that step lands -- but warn so a broken skill link is
  # not a silent mystery for whoever runs setup before then.
  if [ ! -e "$HV_ROOT/claude/skills/hv-toolbelt" ]; then
    hv::warn "hv-toolbelt skill not present in this checkout yet; linking anyway"
  fi
  hv::link "$HV_ROOT/claude/skills/hv-toolbelt" "$HV_CLAUDE_HOME/skills/hv-toolbelt"

  # Dry-run mode: state what we would do and touch nothing. hv::run already
  # no-ops the symlinks above; do the same for the CLAUDE.md edit so a
  # preview cannot claim a write that never happened.
  if [ "${HV_DRY_RUN:-0}" = "1" ]; then
    hv::log "would ensure ~/.claude/CLAUDE.md imports the house rules"
  elif [ ! -f "$HV_CLAUDE_HOME/CLAUDE.md" ]; then
    if printf '%s\n' "$HV_IMPORT_LINE" > "$HV_CLAUDE_HOME/CLAUDE.md"; then
      hv::ok "created ~/.claude/CLAUDE.md"
    else
      hv::warn "could not create ~/.claude/CLAUDE.md"
    fi
  elif grep -q "house-rules.md" "$HV_CLAUDE_HOME/CLAUDE.md"; then
    hv::ok "house rules already imported"
  else
    local tmp="$HV_CLAUDE_HOME/CLAUDE.md.tmp.$$"
    if { printf '%s\n\n' "$HV_IMPORT_LINE"; cat "$HV_CLAUDE_HOME/CLAUDE.md"; } > "$tmp" \
        && mv "$tmp" "$HV_CLAUDE_HOME/CLAUDE.md"; then
      hv::ok "added house rules import to your existing CLAUDE.md"
    else
      hv::warn "could not update ~/.claude/CLAUDE.md"
      rm -f "$tmp"
    fi
  fi

  hv::run claude plugin install superpowers@claude-plugins-official \
    || hv::warn "could not install the superpowers plugin; install it manually"

  return 0
}
