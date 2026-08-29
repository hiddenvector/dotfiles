#!/usr/bin/env bash
# Homebrew is the one shared mutable resource on a multi-account Mac.

export HV_STEP_NAME="homebrew"
export HV_STEP_SCOPE="system"

HV_BREW_PREFIX="${HV_BREW_PREFIX:-/opt/homebrew}"

hv::_brew() { "$HV_BREW_PREFIX/bin/brew" "$@"; }

hv::_brew_installed() { [ -x "$HV_BREW_PREFIX/bin/brew" ]; }

hv::_install_homebrew() {
  if [ "${HV_DRY_RUN:-0}" = "1" ]; then
    hv::log "would run: the Homebrew installer from raw.githubusercontent.com"
    return 0
  fi
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

hv_step_check() {
  hv::_brew_installed || return 1
  hv::_brew bundle check --file "$HV_ROOT/brew/core.Brewfile" >/dev/null 2>&1
}

hv::_offer_shared_write() {
  hv::warn "$HV_BREW_PREFIX was installed by another account and is not writable by you."
  hv::log "Without write access you can run every Homebrew binary but cannot"
  hv::log "install new ones."
  hv::log ""
  hv::log "Tradeoff: sharing write access means any admin user can place"
  hv::log "executables that another admin later runs. Reasonable between"
  hv::log "trusted users on a shared Mac; not otherwise."
  if hv::confirm "Share write access with the admin group?" n; then
    hv::run sudo chgrp -R admin "$HV_BREW_PREFIX"
    hv::run sudo chmod -R g+w "$HV_BREW_PREFIX"
    hv::ok "admin group can now write $HV_BREW_PREFIX"
    return 0
  fi
  hv::log "Leaving read-only. Missing packages will be reported, not installed."
  return 1
}

hv_step_run() {
  hv::step 20 "homebrew"

  if ! hv::_brew_installed; then
    hv::log "Installing Homebrew…"
    hv::run hv::_install_homebrew
  fi

  if [ ! -w "$HV_BREW_PREFIX" ]; then
    hv::_offer_shared_write || {
      hv::_brew bundle check --file "$HV_ROOT/brew/core.Brewfile" \
        || hv::warn "core packages missing; ask the account that owns Homebrew to install them"
      return 0
    }
  fi

  if hv::run hv::_brew bundle --file "$HV_ROOT/brew/core.Brewfile"; then
    hv::ok "core packages"
  else
    hv::warn "core package installation failed — run 'hv setup --only homebrew' after fixing"
  fi
  return 0
}
