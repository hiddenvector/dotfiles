#!/usr/bin/env bash
# Machine facts, always derived from the system. Never cached to disk:
# two accounts on one Mac must not hold two drifting copies of one fact.

HV_MACHINE_NAMES="prometheus atlas hestia kalliope hyperion theseus daedalus \
selene orion helios nyx eos"

hv::machine_name() {
  scutil --get ComputerName 2>/dev/null || true
}

# macOS defaults look like "Marks-MacBook-Pro", "Mac Studio", "Mark's MacBook Air".
hv::machine_has_default_name() {
  local name curly
  name="$(hv::machine_name)"
  [ -z "$name" ] && return 0
  curly="$(printf '\xe2\x80\x99')"
  case "$name" in
    *MacBook*|*iMac*|*Mac-Studio*|*"Mac Studio"*|*Mac-mini*|*"Mac mini"*|*Mac-Pro*|*"Mac Pro"*)
      return 0 ;;
    *"'s "*|*"${curly}s "*)
      return 0 ;;
  esac
  return 1
}

hv::is_managed() {
  profiles status -type enrollment 2>/dev/null | grep -q ': Yes'
}

hv::is_admin() {
  id -Gn 2>/dev/null | tr ' ' '\n' | grep -qx admin
}

hv::arch() { uname -m; }

hv::has_touchid_sensor() {
  bioutil -r >/dev/null 2>&1
}

# Hardware-derived, not account- or config-derived: nothing here is synced
# between a person's Macs, so this is the only per-machine fact available
# to differentiate them without asking a network. Never cached to disk, for
# the same reason as every other fact in this file.
hv::_hardware_seed() {
  ioreg -d2 -c IOPlatformExpertDevice 2>/dev/null \
    | awk -F'"' '/IOPlatformUUID/ { print $4; exit }'
}

# The naive version of this picked the first name in the list that was not
# the machine's *current* name -- fine for one Mac, but two freshly-imaged
# Macs both start with a generic current name (e.g. "Marks-MacBook-Pro" vs
# "Marks-Mac-Studio"), so both landed on the same first suggestion
# ("prometheus"). Step 30 names the signing key after the machine name, so
# two identically-suggested-and-accepted machines collide on key filename
# and GitHub key title. Rotating the list by a hash of a hardware-unique,
# never-synced identifier (the platform UUID) gives two different physical
# Macs different starting points deterministically, with no network call
# and no state to keep in sync -- it does not guarantee uniqueness (a
# person is still free to type the same name for both, and should not),
# but it removes the collision as the *default* offered to both.
hv::suggest_machine_name() {
  local current seed hash count start name

  current="$(hv::machine_name)"
  # bash 3.2 has no arrays; use positional parameters instead. Splitting on
  # whitespace is exactly what turns the space-separated name list into
  # separate positional params -- not an accident to quote away.
  # shellcheck disable=SC2086
  set -- $HV_MACHINE_NAMES
  count=$#

  start=0
  seed="$(hv::_hardware_seed)"
  if [ -n "$seed" ] && [ "$count" -gt 0 ]; then
    hash="$(printf '%s' "$seed" | cksum | awk '{print $1}')"
    start=$((hash % count))
  fi

  while [ "$start" -gt 0 ]; do
    set -- "$@" "$1"
    shift
    start=$((start - 1))
  done

  for name in "$@"; do
    if [ "$name" != "$current" ]; then
      printf '%s\n' "$name"
      return 0
    fi
  done
}
