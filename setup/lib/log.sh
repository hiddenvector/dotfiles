#!/usr/bin/env bash
# Output formatting and the dry-run gate. Source, do not execute.

hv::log()  { printf '%s\n' "       $*"; }
hv::ok()   { printf '%s\n' "       ✓ $*"; }
hv::warn() { printf '%s\n' "       ⚠ $*" >&2; }
hv::err()  { printf '%s\n' "       ✗ $*" >&2; }

hv::step() { printf '\n  [%s] %s\n' "$1" "$2"; }

hv::die() { hv::err "$*"; exit 1; }

# Every mutation in this codebase goes through here.
hv::run() {
  if [ "${HV_DRY_RUN:-0}" = "1" ]; then
    hv::log "would run: $*"
    return 0
  fi
  "$@"
}
