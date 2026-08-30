#!/usr/bin/env bash
# Prompts. Source, do not execute.

hv::ask() {
  local question="$1" default="$2" answer=""
  if [ "${HV_YES:-0}" = "1" ]; then
    printf '%s\n' "$default"
    return 0
  fi
  printf '       %s [%s]: ' "$question" "$default" >&2
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
  printf '       %s %s: ' "$question" "$hint" >&2
  read -r answer || true
  answer="${answer:-$default}"
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# For outward-facing actions (creating repos, uploading keys). --yes must not
# be able to trigger these; with no input available, decline. Unlike
# hv::confirm's [Yy]* prefix match, this requires the exact word "y" or
# "yes" (case-insensitive) -- a prefix match would read "yesterday" or
# "Y2K" as consent in front of a live GitHub mutation.
hv::confirm_always() {
  local question="$1" answer="" normalized
  printf '       %s [y/N]: ' "$question" >&2
  read -r answer || return 1
  normalized="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in y|yes) return 0 ;; *) return 1 ;; esac
}
