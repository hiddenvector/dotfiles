#!/usr/bin/env bash
# House rules compose with whatever the person already has: the repo's
# rules are linked and referenced by one @import line, prepended, never
# written over theirs. settings.json has no import mechanism, so when
# someone already has one it is left alone entirely rather than merged.

export HV_STEP_NAME="agents"
export HV_STEP_SCOPE="user"

HV_CLAUDE_HOME="${HV_CLAUDE_HOME:-$HOME/.claude}"
HV_IMPORT_LINE="@~/.claude/hv/house-rules.md"

hv_step_check() {
  hv::linked "$HV_ROOT/claude/CLAUDE.md" "$HV_CLAUDE_HOME/hv/house-rules.md" \
    && grep -q "house-rules.md" "$HV_CLAUDE_HOME/CLAUDE.md" 2>/dev/null \
    && hv::linked "$HV_ROOT/claude/skills/hv-toolbelt" "$HV_CLAUDE_HOME/skills/hv-toolbelt"
}

# settings.json has no @import equivalent, so it cannot compose the way
# CLAUDE.md does. Ours becomes the default only when nothing exists yet.
# An existing one -- someone's model choice, statusline, plugin set -- is
# never touched: hv::link's rename-and-replace is right for every other
# file this step manages, but wrong for personal settings with no merge
# story. A merge here has to be a human decision.
hv::_install_settings() {
  local dst="$HV_CLAUDE_HOME/settings.json"
  local src="$HV_ROOT/claude/settings.json"

  # No settings yet: ours becomes the default.
  if [ ! -e "$dst" ]; then
    hv::link "$src" "$dst"
    return 0
  fi

  # Already ours: nothing to do.
  if hv::linked "$src" "$dst"; then
    return 0
  fi

  # Theirs. Leave it alone; drop our suggestion alongside it instead.
  hv::link "$src" "$HV_CLAUDE_HOME/settings.hv.json"
  hv::warn "you already have ~/.claude/settings.json — left it alone"
  hv::log "Hidden Vector's suggested settings are at ~/.claude/settings.hv.json"
  hv::log "Merge anything you want from it by hand."
  return 0
}

hv_step_run() {
  hv::step 80 "agents"

  hv::link "$HV_ROOT/claude/CLAUDE.md" "$HV_CLAUDE_HOME/hv/house-rules.md"
  hv::_install_settings

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

  # claude has no module gate covering this step's dependency (core.Brewfile
  # carries the claude-code cask precisely so it is always present by the
  # time this runs) -- but a machine that skipped Homebrew entirely, or ran
  # it before this cask existed, still needs a clear way forward rather than
  # the generic failure a missing binary would otherwise produce.
  if command -v claude >/dev/null 2>&1; then
    # superpowers ships from obra/superpowers-marketplace, not the
    # nonexistent claude-plugins-official. Both calls are idempotent.
    hv::run claude plugin marketplace add obra/superpowers-marketplace \
      || hv::warn "could not add the superpowers-marketplace"
    hv::run claude plugin install superpowers@superpowers-marketplace \
      || hv::warn "could not install the superpowers plugin; install it manually"
  else
    hv::warn "claude is not on PATH; skipping the superpowers plugin install"
    hv::log "run 'hv setup --only homebrew' to install it, then re-run 'hv setup --only agents'"
  fi

  return 0
}
