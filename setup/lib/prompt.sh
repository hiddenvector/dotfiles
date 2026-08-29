#!/usr/bin/env bash
# Prompts. Source, do not execute.

hv::ask() {
  local question="$1" default="$2" answer=""
  if [ "${HV_YES:-0}" = "1" ]; then
    printf '%s\n' "$default"
    return 0
  fi
  if [ -t 0 ]; then
    printf '       %s [%s]: ' "$question" "$default" >&2
  fi
  read -r answer || true
  printf '%s\n' "${answer:-$default}"
}

hv::confirm() {
  local question="$1" default="${2:-n}" answer=""
  if [ "${HV_YES:-0}" = "1" ]; then
    [ "$default" = "y" ]
    return $?
  fi
  local hint="[y/N]"
  [ "$default" = "y" ] && hint="[Y/n]"
  if [ -t 0 ]; then
    printf '       %s %s: ' "$question" "$hint" >&2
  fi
  read -r answer || true
  answer="${answer:-$default}"
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# For outward-facing actions (creating repos, uploading keys). --yes must not
# be able to trigger these; with no input available, decline.
hv::confirm_always() {
  local question="$1" answer=""
  if [ -t 0 ]; then
    printf '       %s [y/N]: ' "$question" >&2
  fi
  read -r answer || return 1
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}
