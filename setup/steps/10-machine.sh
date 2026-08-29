#!/usr/bin/env bash
# Machine name is the per-machine identifier and shows up in the prompt.
# Overlay configuration is step 35 — it needs gh auth from step 30.

export HV_STEP_NAME="machine"
export HV_STEP_SCOPE="system"

hv_step_check() {
  [ -n "$(hv::config_get HV_MODULES)" ]
}

hv::_set_machine_name() {
  local name="$1"
  if ! hv::run sudo scutil --set ComputerName "$name" 2>/dev/null; then
    hv::warn "blocked — scutil unavailable; name recorded for config only"
    return 0
  fi
  hv::run sudo scutil --set HostName "$name" 2>/dev/null || true
  hv::run sudo scutil --set LocalHostName "$name" 2>/dev/null || true
  hv::ok "ComputerName / HostName / LocalHostName -> $name"
}

hv::_choose_modules() {
  local existing m enabled selected=""
  existing="$(hv::config_get HV_MODULES)"
  existing="${existing:-core swift web python security apps}"
  for m in $HV_ALL_MODULES; do
    if [ "$m" = "core" ]; then selected="core"; continue; fi
    case " $existing " in *" $m "*) enabled=y ;; *) enabled=n ;; esac
    if hv::confirm "  enable module: $m" "$enabled"; then
      selected="$selected $m"
    fi
  done
  printf '%s\n' "$selected"
}

hv_step_run() {
  hv::step 10 "machine"

  # Dry-run mode: state what we would do and exit early.
  if [ "${HV_DRY_RUN:-0}" = "1" ]; then
    hv::log "would prompt for machine name and modules"
    hv::log "would write config to $(hv::config_file)"
    return 0
  fi

  local current suggestion name
  current="$(hv::machine_name)"

  if hv::machine_has_default_name; then
    suggestion="$(hv::suggest_machine_name)"
    hv::log "This Mac is named \"${current:-unset}\"."
    hv::log "Hidden Vector machines get proper names — it is the key for"
    hv::log "per-machine config, and it shows up in your prompt."
    hv::log "Suggestions: $HV_MACHINE_NAMES"
    name="$(hv::ask "Machine name" "$suggestion")"
    hv::_set_machine_name "$name"
  else
    hv::ok "$current"
  fi

  hv::config_set HV_MODULES "$(hv::_choose_modules)"

  if hv::is_managed; then
    hv::config_set HV_RESTRICTED "1"
    hv::ok "restricted mode (MDM-managed)"
  fi

  hv::ok "$(hv::config_file)"
  return 0
}
