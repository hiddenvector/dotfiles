#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
}

@test "hv::machine_name reads ComputerName from scutil" {
  hv_stub scutil 0 "prometheus"
  run hv::machine_name
  [ "$output" = "prometheus" ]
  hv_assert_called "--get ComputerName"
}

@test "hv::machine_name is empty when scutil fails" {
  hv_stub scutil 1 ""
  run hv::machine_name
  [ "$output" = "" ]
}

@test "hv::machine_has_default_name detects a stock hostname" {
  hv_stub scutil 0 "Marks-MacBook-Pro"
  run hv::machine_has_default_name
  [ "$status" -eq 0 ]
}

@test "hv::machine_has_default_name detects an apostrophe name" {
  hv_stub scutil 0 "Mark's Mac Studio"
  run hv::machine_has_default_name
  [ "$status" -eq 0 ]
}

@test "hv::machine_has_default_name accepts a proper name" {
  hv_stub scutil 0 "prometheus"
  run hv::machine_has_default_name
  [ "$status" -eq 1 ]
}

@test "hv::is_managed is true when enrolled" {
  hv_stub profiles 0 "Enrolled via DEP: Yes"
  run hv::is_managed
  [ "$status" -eq 0 ]
}

@test "hv::is_managed is false when not enrolled" {
  hv_stub profiles 0 "Enrolled via DEP: No
MDM enrollment: No"
  run hv::is_managed
  [ "$status" -eq 1 ]
}

@test "hv::is_admin is true when in the admin group" {
  hv_stub id 0 "staff admin everyone"
  run hv::is_admin
  [ "$status" -eq 0 ]
}

@test "hv::is_admin is false otherwise" {
  hv_stub id 0 "staff everyone"
  run hv::is_admin
  [ "$status" -eq 1 ]
}

@test "hv::has_touchid_sensor is false on hardware without one" {
  hv_stub bioutil 1 ""
  run hv::has_touchid_sensor
  [ "$status" -eq 1 ]
}

@test "hv::suggest_machine_name returns a greek name" {
  hv_stub scutil 0 "Marks-MacBook-Pro"
  run hv::suggest_machine_name
  [ -n "$output" ]
  [[ "$output" =~ ^[a-z]+$ ]]
}
