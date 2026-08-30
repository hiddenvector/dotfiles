#!/usr/bin/env bash
# Module bundles, then the overlay's. HV_RESTRICTED means exactly one thing:
# do not shell out to `code --install-extension`, which corporate SSL
# inspection breaks.

export HV_STEP_NAME="packages"
export HV_STEP_SCOPE="user"

HV_BREW_PREFIX="${HV_BREW_PREFIX:-/opt/homebrew}"

# Pull the tap name out of Homebrew's refusal, e.g. "Error: Refusing to
# load formula supabase/tap/supabase from untrusted tap supabase/tap." ->
# "supabase/tap". Defensive: if Homebrew's wording changes and nothing
# matches, prints nothing so the caller falls back to the generic failure
# message instead of guessing.
hv::_untrusted_tap() {
  printf '%s\n' "$1" | sed -n 's/.*from untrusted tap \([^[:space:].]*\)\..*/\1/p' | head -n1
}

# Modeled on 20-homebrew.sh's hv::_offer_shared_write: state the tradeoff,
# default to no, and make declining a normal outcome with a path forward.
hv::_offer_trust_tap() {
  local tap="$1"

  # Dry-run mode: state what we would ask and decline, same as a real "no"
  # -- the confirm below blocks on stdin for real and must never run under
  # a preview.
  if [ "${HV_DRY_RUN:-0}" = "1" ]; then
    hv::log "would prompt to trust the untrusted tap '$tap'"
    return 1
  fi

  hv::warn "Homebrew refused to load a formula from the untrusted tap '$tap'."
  hv::log "Trusting a tap lets it run arbitrary code at install time -- its"
  hv::log "install scripts run with your privileges, the same as any"
  hv::log "package you install."
  hv::log ""
  hv::log "Tradeoff: reasonable for a tap you recognize and mean to use;"
  hv::log "otherwise you're extending Homebrew core's vetting to a third"
  hv::log "party who hasn't earned it."
  if hv::confirm "Trust the '$tap' tap?" n; then
    hv::run "$HV_BREW_PREFIX/bin/brew" trust "$tap"
    hv::ok "trusted $tap"
    return 0
  fi
  hv::log "Leaving untrusted. Run 'brew trust $tap' later to install it."
  return 1
}

# Runs one `brew bundle`, capturing output so a failure can be diagnosed.
# On an untrusted-tap failure, offers to trust it and retries once.
hv::_bundle_exec() {
  local file="$1" out rc tap

  if [ "${HV_DRY_RUN:-0}" = "1" ]; then
    hv::log "would run: brew bundle --file $file"
    return 0
  fi

  rc=0
  out="$("$HV_BREW_PREFIX/bin/brew" bundle --file "$file" 2>&1)" || rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"

  if [ "$rc" -ne 0 ]; then
    tap="$(hv::_untrusted_tap "$out")"
    if [ -n "$tap" ] && hv::_offer_trust_tap "$tap"; then
      hv::log "retrying $file"
      rc=0
      out="$("$HV_BREW_PREFIX/bin/brew" bundle --file "$file" 2>&1)" || rc=$?
      [ -n "$out" ] && printf '%s\n' "$out"
      [ "$rc" -eq 0 ] || hv::warn "still failing after trusting '$tap'"
    fi
  fi
  return "$rc"
}

hv::_bundle() {
  local file="$1"
  [ -f "$file" ] || return 0
  hv::run hv::_bundle_exec "$file"
}

hv_step_check() {
  local m
  for m in $(hv::modules); do
    "$HV_BREW_PREFIX/bin/brew" bundle check \
      --file "$HV_ROOT/brew/$m.Brewfile" >/dev/null 2>&1 || return 1
  done
  return 0
}

hv::_vscode_extensions() {
  local ext
  if [ "$(hv::config_get HV_RESTRICTED)" = "1" ]; then
    hv::warn "restricted mode — install these extensions by hand:"
    while read -r ext; do
      [ -n "$ext" ] && hv::log "    $ext"
    done < "$HV_ROOT/config/vscode-extensions.txt"
    return 0
  fi
  while read -r ext; do
    [ -n "$ext" ] && hv::run code --install-extension "$ext" --force
  done < "$HV_ROOT/config/vscode-extensions.txt"
  [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "VS Code extensions"
}

hv_step_run() {
  hv::step 50 "packages"

  local m overlay f overlay_failed
  for m in $(hv::modules); do
    if hv::_bundle "$HV_ROOT/brew/$m.Brewfile"; then
      [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "$m"
    else
      hv::warn "$m packages failed — re-run 'hv setup --only packages' after fixing"
    fi
  done

  local local_brewfile="${HV_CONFIG_HOME:-$HOME/.config/hv}/local.Brewfile"
  if [ -s "$local_brewfile" ]; then
    if hv::_bundle "$local_brewfile"; then
      [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "local packages"
    else
      hv::warn "local packages failed — re-run 'hv setup --only packages' after fixing"
    fi
  fi

  overlay="$(hv::config_get HV_OVERLAY)"
  if [ -n "$overlay" ] && [ "$overlay" != "none" ] && [ -d "$overlay/brew" ]; then
    overlay_failed=0
    for f in "$overlay"/brew/*.Brewfile; do
      if [ -f "$f" ]; then
        hv::_bundle "$f" || overlay_failed=1
      fi
    done
    if [ "$overlay_failed" -eq 0 ]; then
      [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "overlay packages"
    else
      hv::warn "overlay packages failed — re-run 'hv setup --only packages' after fixing"
    fi
  fi

  if hv::module_enabled apps; then
    hv::_vscode_extensions
  fi
  return 0
}
