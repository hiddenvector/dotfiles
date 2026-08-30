#!/usr/bin/env bash
# Every setting here is per-account: `defaults write` targets
# ~/Library/Preferences. Touch ID is step 05, not here.

export HV_STEP_NAME="macos"
export HV_STEP_SCOPE="user"

# defaults are cheap to reapply and awkward to verify; always converge.
hv_step_check() { return 1; }

hv_step_run() {
  hv::step 60 "macOS defaults"

  # Trackpad — three-finger drag lives in Accessibility, needs both domains.
  hv::run defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -int 1
  hv::run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -int 1
  hv::run defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  hv::run defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
  hv::run defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerDoubleTapGesture -int 1
  hv::run defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 0

  # Keyboard
  hv::run defaults write NSGlobalDomain KeyRepeat -int 2
  hv::run defaults write NSGlobalDomain InitialKeyRepeat -int 15
  hv::run defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  hv::run defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  hv::run defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

  # Dock
  hv::run defaults write com.apple.dock autohide -bool true
  hv::run defaults write com.apple.dock tilesize -int 64

  # Finder
  hv::run defaults write com.apple.finder ShowPathbar -bool true
  hv::run defaults write com.apple.finder FXPreferredViewStyle -string "clmv"
  hv::run defaults write com.apple.finder AppleShowAllFiles -bool true

  hv::run killall Dock 2>/dev/null || true
  hv::run killall Finder 2>/dev/null || true
  [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "trackpad, keyboard, dock, finder"

  local overlay
  overlay="$(hv::config_get HV_OVERLAY)"
  if [ -n "$overlay" ] && [ -x "$overlay/macos.sh" ]; then
    hv::run "$overlay/macos.sh"
    [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "overlay macos.sh"
  fi

  hv::warn "three-finger drag needs a logout to take effect"
  return 0
}
