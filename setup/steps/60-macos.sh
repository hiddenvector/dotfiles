#!/usr/bin/env bash
# Every setting here is per-account: `defaults write` targets
# ~/Library/Preferences. Touch ID is step 05, not here.

export HV_STEP_NAME="macos"
export HV_STEP_SCOPE="user"

# Defaults table: domain|key|write-flag|write-value|expected-read-value
# Booleans read back as 1/0, which is why write and expected differ for them.
HV_MACOS_DEFAULTS='com.apple.AppleMultitouchTrackpad|TrackpadThreeFingerDrag|-int|1|1
com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadThreeFingerDrag|-int|1|1
com.apple.AppleMultitouchTrackpad|Clicking|-bool|true|1
com.apple.AppleMultitouchTrackpad|TrackpadRightClick|-bool|true|1
com.apple.AppleMultitouchTrackpad|TrackpadTwoFingerDoubleTapGesture|-int|1|1
com.apple.AppleMultitouchTrackpad|TrackpadThreeFingerTapGesture|-int|0|0
NSGlobalDomain|KeyRepeat|-int|2|2
NSGlobalDomain|InitialKeyRepeat|-int|15|15
NSGlobalDomain|NSAutomaticSpellingCorrectionEnabled|-bool|false|0
NSGlobalDomain|NSAutomaticCapitalizationEnabled|-bool|false|0
NSGlobalDomain|NSAutomaticPeriodSubstitutionEnabled|-bool|false|0
com.apple.dock|autohide|-bool|true|1
com.apple.dock|tilesize|-int|64|64
com.apple.finder|ShowPathbar|-bool|true|1
com.apple.finder|FXPreferredViewStyle|-string|clmv|clmv
com.apple.finder|AppleShowAllFiles|-bool|true|1'

hv_step_check() {
  local domain key expected
  while IFS='|' read -r domain key _ _ expected; do
    [ -n "$domain" ] || continue
    if ! actual="$(defaults read "$domain" "$key" 2>/dev/null)"; then
      return 1
    fi
    [ "$actual" = "$expected" ] || return 1
  done <<EOF
$HV_MACOS_DEFAULTS
EOF
  return 0
}

hv_step_run() {
  hv::step 60 "macOS defaults"

  local domain key flag value expected actual wrote=0
  while IFS='|' read -r domain key flag value expected; do
    [ -n "$domain" ] || continue
    if actual="$(defaults read "$domain" "$key" 2>/dev/null)" && [ "$actual" = "$expected" ]; then
      continue
    fi
    hv::run defaults write "$domain" "$key" "$flag" "$value"
    wrote=1
  done <<EOF
$HV_MACOS_DEFAULTS
EOF

  [ "$wrote" = "0" ] || {
    hv::run killall Dock 2>/dev/null || true
    hv::run killall Finder 2>/dev/null || true
  }
  [ "${HV_DRY_RUN:-0}" = "1" ] || [ "$wrote" = "0" ] || hv::ok "trackpad, keyboard, dock, finder"

  local overlay
  overlay="$(hv::config_get HV_OVERLAY)"
  if [ -n "$overlay" ] && [ -x "$overlay/macos.sh" ]; then
    if hv::run "$overlay/macos.sh"; then
      [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "overlay macos.sh"
    else
      hv::warn "your overlay's macos.sh failed — $overlay/macos.sh"
    fi
  fi

  hv::warn "three-finger drag needs a logout to take effect"
  return 0
}
