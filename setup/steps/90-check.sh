#!/usr/bin/env bash
# Final report. Untracked personal config with no overlay is drift: it will
# not survive a machine wipe and does not sync between a person's own Macs.

export HV_STEP_NAME="verify"
export HV_STEP_SCOPE="user"

hv::_untracked_personal_config() {
  local f="${HV_CONFIG_HOME:-$HOME/.config/hv}/local.Brewfile"
  # Step 40 creates this file itself now, as a commented stub -- plain
  # non-empty (-s) would make that stub read as "personal packages" the
  # moment setup finishes, on every machine, forever. Only a line that
  # isn't blank or a comment counts as real content.
  grep -qvE '^[[:space:]]*(#.*)?$' "$f" 2>/dev/null
}

hv_step_check() {
  hv::docs_current || return 1
  return 0
}

hv_step_run() {
  hv::step 90 "check"

  hv::docs_current || hv::warn "docs/USAGE.md is stale — run: hv cheatsheet --regenerate"

  local overlay
  overlay="$(hv::config_get HV_OVERLAY)"
  if hv::_untracked_personal_config && { [ -z "$overlay" ] || [ "$overlay" = "none" ]; }; then
    hv::warn "you have personal packages that will not survive a machine wipe"
    hv::log "Run 'hv overlay init' to track them in your own repo."
  fi

  hv::ok "checks complete"
  return 0
}
