#!/usr/bin/env bash
# Fail fast, before anything mutates.

export HV_STEP_NAME="preflight"
export HV_STEP_SCOPE="system"

hv::_clt_present() { xcode-select -p >/dev/null 2>&1; }

hv::_macos_major() { sw_vers -productVersion 2>/dev/null | cut -d. -f1; }

hv_step_check() {
  hv::_clt_present
}

hv_step_run() {
  hv::step 00 "preflight"

  local major arch
  major="$(hv::_macos_major)"
  [ -n "$major" ] && [ "$major" -ge 14 ] 2>/dev/null \
    || hv::die "requires macOS 14 (Sonoma) or later; found ${major:-unknown}"

  arch="$(hv::arch)"
  [ "$arch" = "arm64" ] \
    || hv::die "requires Apple Silicon (arm64); found $arch"

  hv::ok "macOS $major  $arch"

  if ! hv::_clt_present; then
    hv::log "Command Line Tools missing — installing (GUI prompt)…"
    hv::run xcode-select --install || true
    hv::die "rerun hv setup once Command Line Tools finish installing"
  fi
  hv::ok "Command Line Tools"

  if hv::is_admin; then
    hv::ok "admin rights"
  else
    hv::warn "admin rights: limited — system steps will be skipped"
  fi

  hv::is_managed && hv::warn "this machine is MDM-managed"
  return 0
}
