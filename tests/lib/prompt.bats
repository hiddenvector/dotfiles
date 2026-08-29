#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
}

@test "hv::ask returns typed input" {
  run --separate-stderr bash -c "source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo atlas | hv::ask 'Machine name' 'prometheus'"
  [ "$output" = "atlas" ]
}

@test "hv::ask returns the default on empty input" {
  run --separate-stderr bash -c "source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo '' | hv::ask 'Machine name' 'prometheus'"
  [ "$output" = "prometheus" ]
}

@test "hv::ask returns the default without reading under --yes" {
  HV_YES=1
  run --separate-stderr hv::ask "Machine name" "prometheus"
  [ "$output" = "prometheus" ]
}

@test "hv::confirm accepts y" {
  run --separate-stderr bash -c "source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo y | hv::confirm 'Proceed' n"
  [ "$status" -eq 0 ]
}

@test "hv::confirm honours a no default on empty input" {
  run --separate-stderr bash -c "source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo '' | hv::confirm 'Proceed' n"
  [ "$status" -eq 1 ]
}

@test "hv::confirm takes the default under --yes" {
  HV_YES=1
  run --separate-stderr hv::confirm "Proceed" y
  [ "$status" -eq 0 ]
}

@test "hv::confirm_always ignores --yes and still reads input" {
  run --separate-stderr bash -c "export HV_YES=1; source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo n | hv::confirm_always 'Create a public repo'"
  [ "$status" -eq 1 ]
}

@test "hv::confirm_always declines when there is no tty and no input" {
  run --separate-stderr bash -c "export HV_YES=1; source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; hv::confirm_always 'Create a public repo' < /dev/null"
  [ "$status" -eq 1 ]
}

@test "hv::ask writes its prompt to stderr, not stdout" {
  run --separate-stderr bash -c "source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo atlas | hv::ask 'Machine name' 'prometheus'"
  [ "$output" = "atlas" ]
  [[ "$stderr" == *"Machine name"* ]]
}
