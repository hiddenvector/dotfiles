#!/usr/bin/env bash
# Module bundles, then the overlay's. HV_RESTRICTED means exactly one thing:
# do not shell out to `code --install-extension`, which corporate SSL
# inspection breaks.

export HV_STEP_NAME="packages"
export HV_STEP_SCOPE="user"

HV_BREW_PREFIX="${HV_BREW_PREFIX:-/opt/homebrew}"

hv::_bundle() {
  local file="$1"
  [ -f "$file" ] || return 0
  hv::run "$HV_BREW_PREFIX/bin/brew" bundle --file "$file"
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
