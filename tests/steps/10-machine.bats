#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
  hv_stub sudo 0 ""
  hv_stub scutil 0 "prometheus"
  hv_stub profiles 0 "MDM enrollment: No"
  export HV_YES=1
}

@test "check fails when no config exists" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check passes once modules are recorded" {
  hv::config_set HV_MODULES "core web"
  source "$HV_ROOT/setup/steps/10-machine.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "run leaves an already-named machine alone" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  run hv_step_run
  hv_assert_not_called "--set ComputerName"
}

@test "run does not rename a machine with a stock name under --yes" {
  hv_stub scutil 0 "Marks-MacBook-Pro"
  source "$HV_ROOT/setup/steps/10-machine.sh"
  run hv_step_run
  hv_assert_not_called "--set ComputerName"
  hv_assert_not_called "--set HostName"
  hv_assert_not_called "--set LocalHostName"
  [[ "$stderr$output" == *"not renaming it under --yes"* ]]
  [[ "$stderr$output" == *"sudo scutil --set ComputerName"* ]]
}

@test "run renames a machine with a stock name when confirmed interactively" {
  hv_stub scutil 0 "Marks-MacBook-Pro"
  hv_stub_ioreg_uuid "AAAAAAAA-0000-0000-0000-000000000001"
  run bash -c "printf 'newname\n' | { export HV_YES=0; source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/machine.sh'; source '$HV_ROOT/setup/lib/config.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; source '$HV_ROOT/setup/steps/10-machine.sh'; hv_step_run; }"
  hv_assert_called "--set ComputerName newname"
  hv_assert_called "--set HostName newname"
  hv_assert_called "--set LocalHostName newname"
}

@test "run shows the full suggestion list and warns names must be unique across machines" {
  hv_stub scutil 0 "Marks-MacBook-Pro"
  run bash -c "printf 'newname\n' | { export HV_YES=0; source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/machine.sh'; source '$HV_ROOT/setup/lib/config.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; source '$HV_ROOT/setup/steps/10-machine.sh'; hv_step_run; }"
  [[ "$output" == *"Suggestions: prometheus atlas hestia kalliope hyperion theseus daedalus"* ]]
  [[ "$output" == *"other Macs"* ]]
}

@test "run records modules to config" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  hv_step_run
  hv::config_load
  [[ "$HV_MODULES" == *"core"* ]]
}

@test "run marks an MDM machine restricted automatically" {
  hv_stub profiles 0 "MDM enrollment: Yes"
  source "$HV_ROOT/setup/steps/10-machine.sh"
  hv_step_run
  run hv::config_get HV_RESTRICTED
  [ "$output" = "1" ]
}

@test "run degrades when scutil is blocked by MDM" {
  # Create a sudo stub that passes through to scutil for this test
  cat > "$HV_STUB_DIR/sudo" <<SUDO_PASSTHROUGH
#!/usr/bin/env bash
echo "sudo \$*" >> "$HV_STUB_LOG"
"\$@"
SUDO_PASSTHROUGH
  chmod +x "$HV_STUB_DIR/sudo"

  # scutil failing --get ComputerName reads as an unset/default name, so
  # this must go through the interactive rename path (--yes now skips
  # renaming outright) to actually reach the blocked --set call.
  hv_stub scutil 1 ""
  run bash -c "printf 'newname\n' | { export HV_YES=0; source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/machine.sh'; source '$HV_ROOT/setup/lib/config.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; source '$HV_ROOT/setup/steps/10-machine.sh'; hv_step_run; }"
  [ "$status" -eq 0 ]
  [[ "$stderr$output" == *"blocked"* ]]
}

@test "run is idempotent" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  hv_step_run
  local first; first="$(cat "$(hv::config_file)")"
  hv_step_run
  [ "$first" = "$(cat "$(hv::config_file)")" ]
}

@test "step scope is system" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  [ "$HV_STEP_SCOPE" = "system" ]
}

@test "no test in this file reaches a real system command" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  hv_step_run
  hv_assert_no_refusals
}

@test "an un-stubbed dangerous command is refused, not executed" {
  run env PATH="$HV_STUB_DIR:$PATH" networksetup -setairportpower en0 off
  [ "$status" -eq 111 ]
  [[ "$stderr$output" == *"REFUSED"* ]]
}

@test "dry run does not rename the machine or claim it did" {
  hv_stub scutil 0 "Marks-MacBook-Pro"
  HV_DRY_RUN=1
  source "$HV_ROOT/setup/steps/10-machine.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  hv_assert_not_called "--set ComputerName"
}

@test "git clone is refused but local git still works" {
  run git clone https://example.com/repo /tmp/nope
  [ "$status" -eq 111 ]
  cd "$BATS_TEST_TMPDIR" || return 1
  run git init -q scratch
  [ "$status" -eq 0 ]
}

@test "git -C with a network subcommand is refused" {
  run git -C "$BATS_TEST_TMPDIR" push -u origin HEAD
  [ "$status" -eq 111 ]
  run git -C "$BATS_TEST_TMPDIR" pull --ff-only
  [ "$status" -eq 111 ]
}

@test "git -C with a local subcommand still works" {
  git init -q "$BATS_TEST_TMPDIR/scratch"
  run git -C "$BATS_TEST_TMPDIR/scratch" status --porcelain
  [ "$status" -eq 0 ]
}

@test "a commit message containing a denied word is not refused" {
  git init -q "$BATS_TEST_TMPDIR/msg"
  git -C "$BATS_TEST_TMPDIR/msg" config user.email t@t.t
  git -C "$BATS_TEST_TMPDIR/msg" config user.name Test
  run git -C "$BATS_TEST_TMPDIR/msg" commit -q --allow-empty -m "push the button"
  [ "$status" -eq 0 ]
}
