#!/usr/bin/env bash
# Per-user preferences. Machine facts belong in machine.sh, not here.

HV_ALL_MODULES="core swift web python security apps"

hv::config_file() {
  printf '%s\n' "${HV_CONFIG_HOME:-$HOME/.config/hv}/config"
}

hv::config_load() {
  local file
  file="$(hv::config_file)"
  # shellcheck disable=SC1090
  [ -f "$file" ] && . "$file"
  HV_MODULES="${HV_MODULES:-core}"
  HV_OVERLAY="${HV_OVERLAY:-}"
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
