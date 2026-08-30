#!/usr/bin/env bash
# Per-user preferences. Machine facts belong in machine.sh, not here.

HV_ALL_MODULES="core swift web python security apps"

hv::config_file() {
  printf '%s\n' "${HV_CONFIG_HOME:-$HOME/.config/hv}/config"
}

# Refreshes only the config keys this codebase actually owns
# (HV_MODULES/HV_OVERLAY/HV_RESTRICTED), read back one at a time via
# hv::config_get instead of `.`-sourcing the file wholesale.
#
# This used to source the file directly. That was fine for the original
# single call at bin/hv startup (before main() parses --dry-run/--yes), but
# hv::cmd_setup now calls hv::config_load again after every step so that
# module selections a step just wrote (via hv::config_set, from its own
# subshell) reach later steps in the same run -- see the regression test
# "module selection from step 10 reaches a later step in the same hv setup
# run" in tests/bin/hv.bats. Sourcing the file at that point runs with
# command-line flags already parsed and exported, so any assignment the
# file happened to contain -- HV_DRY_RUN, HV_YES, anything -- would
# silently override them for every remaining step. That's a real hazard
# here specifically because ~/.config/hv/config is documented, hand-edited
# user config that zsh/.zshrc also sources; it was never meant to be a
# trusted, closed set of keys.
#
# Reading back just the three keys this file is documented to hold makes a
# hand-edited config unable to inject *any* other variable into the running
# process, not only HV_DRY_RUN/HV_YES -- so it stays safe to reload after
# every step, no matter what future flags get added. hv::config_get already
# has to parse `KEY="value"` lines (round-tripping values with spaces, used
# elsewhere for HV_OVERLAY_URL/HV_RESTRICTED), so this is the same parsing
# hv::config_set's own writer produces -- nothing new to keep in sync.
hv::config_load() {
  HV_MODULES="$(hv::config_get HV_MODULES)"
  HV_MODULES="${HV_MODULES:-core}"
  HV_OVERLAY="$(hv::config_get HV_OVERLAY)"
  HV_OVERLAY="${HV_OVERLAY:-}"
  HV_RESTRICTED="$(hv::config_get HV_RESTRICTED)"
  HV_RESTRICTED="${HV_RESTRICTED:-}"
}

hv::config_get() {
  local key="$1" file
  file="$(hv::config_file)"
  [ -f "$file" ] || return 0
  sed -n "s/^${key}=\"\\(.*\\)\"\$/\\1/p" "$file" | tail -1
}

hv::config_set() {
  local key="$1" value="$2" file tmp
  file="$(hv::config_file)"
  hv::run mkdir -p "$(dirname "$file")"
  [ "${HV_DRY_RUN:-0}" = "1" ] && { hv::log "would set $key"; return 0; }
  [ -f "$file" ] || printf '# Hidden Vector user config. Machine facts are derived, not stored.\n' > "$file"
  tmp="$file.tmp.$$"
  grep -v "^${key}=" "$file" > "$tmp" || true
  printf '%s="%s"\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

# core is mandatory and always first; order otherwise follows HV_ALL_MODULES.
hv::modules() {
  local m
  : "${HV_MODULES:?hv::config_load must be called before hv::modules}"
  printf '%s\n' core
  for m in $HV_ALL_MODULES; do
    [ "$m" = "core" ] && continue
    case " $HV_MODULES " in *" $m "*) printf '%s\n' "$m" ;; esac
  done
}

hv::module_enabled() {
  hv::modules | grep -qx "$1"
}
