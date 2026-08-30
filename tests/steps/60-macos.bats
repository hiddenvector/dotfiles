#!/usr/bin/env bats

load ../helper

# Custom defaults stub that returns matching values to make check pass.
# Use if statements instead of case/pipe pattern which bash interprets as OR.
make_defaults_stub_matching() {
  mkdir -p "$HV_STUB_DIR"
  cat > "$HV_STUB_DIR/defaults" <<'STUB'
#!/usr/bin/env bash
echo "defaults $*" >> "$HV_STUB_LOG"
mode="$1"
domain="$2"
key="$3"

# Return matching values for each key
if [ "$mode" = "read" ]; then
  case "$domain:$key" in
    com.apple.AppleMultitouchTrackpad:TrackpadThreeFingerDrag) echo "1"; exit 0 ;;
    com.apple.driver.AppleBluetoothMultitouch.trackpad:TrackpadThreeFingerDrag) echo "1"; exit 0 ;;
    com.apple.AppleMultitouchTrackpad:Clicking) echo "1"; exit 0 ;;
    com.apple.AppleMultitouchTrackpad:TrackpadRightClick) echo "1"; exit 0 ;;
    com.apple.AppleMultitouchTrackpad:TrackpadTwoFingerDoubleTapGesture) echo "1"; exit 0 ;;
    com.apple.AppleMultitouchTrackpad:TrackpadThreeFingerTapGesture) echo "0"; exit 0 ;;
    NSGlobalDomain:KeyRepeat) echo "2"; exit 0 ;;
    NSGlobalDomain:InitialKeyRepeat) echo "15"; exit 0 ;;
    NSGlobalDomain:NSAutomaticSpellingCorrectionEnabled) echo "0"; exit 0 ;;
    NSGlobalDomain:NSAutomaticCapitalizationEnabled) echo "0"; exit 0 ;;
    NSGlobalDomain:NSAutomaticPeriodSubstitutionEnabled) echo "0"; exit 0 ;;
    com.apple.dock:autohide) echo "1"; exit 0 ;;
    com.apple.dock:tilesize) echo "64"; exit 0 ;;
    com.apple.finder:ShowPathbar) echo "1"; exit 0 ;;
    com.apple.finder:FXPreferredViewStyle) echo "clmv"; exit 0 ;;
    com.apple.finder:AppleShowAllFiles) echo "1"; exit 0 ;;
    *) echo "0"; exit 0 ;;
  esac
elif [ "$mode" = "write" ]; then
  exit 0
else
  exit 0
fi
STUB
  chmod +x "$HV_STUB_DIR/defaults"
}

# Custom defaults stub that returns a mismatched value for one key (KeyRepeat)
make_defaults_stub_drifted() {
  mkdir -p "$HV_STUB_DIR"
  cat > "$HV_STUB_DIR/defaults" <<'STUB'
#!/usr/bin/env bash
echo "defaults $*" >> "$HV_STUB_LOG"
mode="$1"
domain="$2"
key="$3"

if [ "$mode" = "read" ]; then
  case "$domain:$key" in
    NSGlobalDomain:KeyRepeat) echo "5"; exit 0 ;;
    com.apple.AppleMultitouchTrackpad:TrackpadThreeFingerDrag) echo "1"; exit 0 ;;
    com.apple.driver.AppleBluetoothMultitouch.trackpad:TrackpadThreeFingerDrag) echo "1"; exit 0 ;;
    com.apple.AppleMultitouchTrackpad:Clicking) echo "1"; exit 0 ;;
    com.apple.AppleMultitouchTrackpad:TrackpadRightClick) echo "1"; exit 0 ;;
    com.apple.AppleMultitouchTrackpad:TrackpadTwoFingerDoubleTapGesture) echo "1"; exit 0 ;;
    com.apple.AppleMultitouchTrackpad:TrackpadThreeFingerTapGesture) echo "0"; exit 0 ;;
    NSGlobalDomain:InitialKeyRepeat) echo "15"; exit 0 ;;
    NSGlobalDomain:NSAutomaticSpellingCorrectionEnabled) echo "0"; exit 0 ;;
    NSGlobalDomain:NSAutomaticCapitalizationEnabled) echo "0"; exit 0 ;;
    NSGlobalDomain:NSAutomaticPeriodSubstitutionEnabled) echo "0"; exit 0 ;;
    com.apple.dock:autohide) echo "1"; exit 0 ;;
    com.apple.dock:tilesize) echo "64"; exit 0 ;;
    com.apple.finder:ShowPathbar) echo "1"; exit 0 ;;
    com.apple.finder:FXPreferredViewStyle) echo "clmv"; exit 0 ;;
    com.apple.finder:AppleShowAllFiles) echo "1"; exit 0 ;;
    *) echo "0"; exit 0 ;;
  esac
elif [ "$mode" = "write" ]; then
  exit 0
else
  exit 0
fi
STUB
  chmod +x "$HV_STUB_DIR/defaults"
}

# Custom defaults stub that fails all reads (so run will write everything)
make_defaults_stub_write_all() {
  mkdir -p "$HV_STUB_DIR"
  cat > "$HV_STUB_DIR/defaults" <<'STUB'
#!/usr/bin/env bash
echo "defaults $*" >> "$HV_STUB_LOG"
mode="$1"
case "$mode" in
  read) exit 1 ;;
  write) exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$HV_STUB_DIR/defaults"
}

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  # Default to matching stub so tests that write unconditionally will still work
  make_defaults_stub_matching
  hv_stub killall 0 ""
}

@test "check passes when every default already matches" {
  make_defaults_stub_matching
  hv_stub killall 0 ""
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "check fails when a default does not match" {
  make_defaults_stub_drifted
  hv_stub killall 0 ""
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_check
  [ "$status" -ne 0 ]
}

@test "run does not restart Dock or Finder when nothing changed" {
  make_defaults_stub_matching
  hv_stub killall 0 ""
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_not_called "killall"
}

@test "run restarts Dock and Finder when it wrote something" {
  make_defaults_stub_write_all
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_called "killall Dock"
  hv_assert_called "killall Finder"
}

@test "run writes trackpad, keyboard, dock and finder defaults" {
  make_defaults_stub_write_all
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_called "TrackpadThreeFingerDrag"
  hv_assert_called "KeyRepeat"
  hv_assert_called "com.apple.dock autohide"
  hv_assert_called "ShowPathbar"
}

@test "run does not touch Touch ID — that is step 05" {
  make_defaults_stub_write_all
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_not_called "pam_tid"
  hv_assert_not_called "sudo_local"
}

@test "run applies the overlay's macos.sh when present" {
  make_defaults_stub_write_all
  mkdir -p "$HOME/overlay"
  echo 'echo overlay-macos-ran' > "$HOME/overlay/macos.sh"
  chmod +x "$HOME/overlay/macos.sh"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  [[ "$output" == *"overlay-macos-ran"* ]]
}

@test "a failing overlay macos.sh warns and does not claim success" {
  make_defaults_stub_write_all
  mkdir -p "$HOME/overlay"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$HOME/overlay/macos.sh"
  chmod +x "$HOME/overlay/macos.sh"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  case "$stderr$output" in *"macos.sh failed"*) : ;; *) return 1 ;; esac
  case "$output" in *"✓ overlay macos.sh"*) return 1 ;; esac
}

@test "run warns that three-finger drag needs a logout" {
  make_defaults_stub_write_all
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  [[ "$stderr$output" == *"logout"* ]]
}

@test "run under dry run writes nothing" {
  make_defaults_stub_write_all
  HV_DRY_RUN=1
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_not_called "defaults write"
  [[ ! "$output" =~ "trackpad, keyboard, dock, finder" ]]
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/60-macos.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
