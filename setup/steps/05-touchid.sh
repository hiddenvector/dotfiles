#!/usr/bin/env bash
# Runs before every other sudo-requiring step, so the password is typed once.
# /etc/pam.d/sudo_local survives macOS updates; /etc/pam.d/sudo does not.

export HV_STEP_NAME="touchid"
export HV_STEP_SCOPE="system"

HV_PAM_FILE="${HV_PAM_FILE:-/etc/pam.d/sudo_local}"

hv_step_check() {
  [ -f "$HV_PAM_FILE" ] || return 1
  grep -q "pam_tid.so" "$HV_PAM_FILE"
}

hv_step_run() {
  hv::step 05 "Touch ID for sudo"

  if hv_step_check; then
    hv::ok "already enabled"
    return 0
  fi

  # A Mac Studio has no built-in sensor: the PAM file would be inert.
  if ! hv::has_touchid_sensor; then
    hv::warn "no Touch ID sensor on this Mac"
    hv::log "Works via a Magic Keyboard with Touch ID. Connect one, then:"
    hv::log "  hv setup --only touchid"
    return 0
  fi

  # Dry-run mode: state what we would do and exit early.
  if [ "${HV_DRY_RUN:-0}" = "1" ]; then
    hv::log "would write Touch ID PAM config to $HV_PAM_FILE"
    return 0
  fi

  hv::log "This is the only time you'll type your password."
  if ! echo "auth       sufficient     pam_tid.so" \
      | hv::run sudo tee "$HV_PAM_FILE" >/dev/null 2>&1; then
    hv::warn "blocked — cannot write $HV_PAM_FILE"
    hv::log "Your MDM controls PAM. Continuing with password auth."
    return 0
  fi

  hv::ok "$HV_PAM_FILE written"
  hv::log "Active for sudo in Terminal, iTerm and VS Code."
  hv::log "Not over SSH. tmux needs pam_reattach — see docs/USAGE.md."
  return 0
}
