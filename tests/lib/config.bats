#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
}

@test "hv::config_set creates the file and stores a value" {
  hv::config_set HV_MODULES "core web"
  [ -f "$(hv::config_file)" ]
  run hv::config_get HV_MODULES
  [ "$output" = "core web" ]
}

@test "hv::config_set replaces rather than appends" {
  hv::config_set HV_MODULES "core"
  hv::config_set HV_MODULES "core web python"
  run grep -c '^HV_MODULES=' "$(hv::config_file)"
  [ "$output" = "1" ]
  run hv::config_get HV_MODULES
  [ "$output" = "core web python" ]
}

@test "hv::config_get is empty for an unset key" {
  run hv::config_get HV_OVERLAY
  [ "$output" = "" ]
}

@test "hv::config_load defaults modules to core" {
  hv::config_load
  [ "$HV_MODULES" = "core" ]
}

@test "hv::modules always puts core first" {
  hv::config_set HV_MODULES "web core swift"
  hv::config_load
  run hv::modules
  [ "${lines[0]}" = "core" ]
}

@test "hv::modules deduplicates" {
  hv::config_set HV_MODULES "core core web web"
  hv::config_load
  run hv::modules
  [ "${#lines[@]}" -eq 2 ]
}

@test "hv::modules adds core when it was omitted" {
  hv::config_set HV_MODULES "web"
  hv::config_load
  run hv::modules
  [ "${lines[0]}" = "core" ]
  [ "${lines[1]}" = "web" ]
}

@test "hv::module_enabled reflects the config" {
  hv::config_set HV_MODULES "core web"
  hv::config_load
  run hv::module_enabled web
  [ "$status" -eq 0 ]
  run hv::module_enabled swift
  [ "$status" -eq 1 ]
}

@test "config values containing spaces survive a round trip" {
  hv::config_set HV_OVERLAY "/path/with spaces/repo"
  hv::config_load
  [ "$HV_OVERLAY" = "/path/with spaces/repo" ]
}
