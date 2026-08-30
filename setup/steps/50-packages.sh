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
  hv::ok "VS Code extensions"
}

hv_step_run() {
  hv::step 50 "packages"

  local m overlay f
  for m in $(hv::modules); do
    hv::_bundle "$HV_ROOT/brew/$m.Brewfile"
    hv::ok "$m"
  done

  overlay="$(hv::config_get HV_OVERLAY)"
  if [ -n "$overlay" ] && [ "$overlay" != "none" ] && [ -d "$overlay/brew" ]; then
    for f in "$overlay"/brew/*.Brewfile; do
      [ -f "$f" ] && hv::_bundle "$f"
    done
    hv::ok "overlay packages"
  fi

  hv::module_enabled apps && hv::_vscode_extensions
  return 0
}
