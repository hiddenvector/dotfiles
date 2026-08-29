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

hv::suggest_machine_name() {
  local current name
  current="$(hv::machine_name)"
  for name in $HV_MACHINE_NAMES; do
    if [ "$name" != "$current" ]; then
      printf '%s\n' "$name"
      return 0
    fi
  done
}
