#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  # A private step directory so tests do not depend on real steps.
  export HV_STEPS_DIR="$BATS_TEST_TMPDIR/steps"
  mkdir -p "$HV_STEPS_DIR"
  cat > "$HV_STEPS_DIR/10-alpha.sh" <<'STEP'
HV_STEP_NAME="alpha"
HV_STEP_SCOPE="user"
hv_step_check() { [ -f "$HOME/alpha.done" ]; }
hv_step_run() { echo ran-alpha; touch "$HOME/alpha.done"; }
STEP
  cat > "$HV_STEPS_DIR/20-beta.sh" <<'STEP'
HV_STEP_NAME="beta"
HV_STEP_SCOPE="system"
hv_step_check() { [ -f "$HOME/beta.done" ]; }
hv_step_run() { echo ran-beta; touch "$HOME/beta.done"; }
STEP
}

@test "hv setup runs every drifted step in filename order" {
  run "$HV_ROOT/bin/hv" setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran-alpha"* ]]
  [[ "$output" == *"ran-beta"* ]]
  [[ "${output%%ran-beta*}" == *"ran-alpha"* ]]
}

@test "hv setup skips steps that are already converged" {
  touch "$HOME/alpha.done"
  run "$HV_ROOT/bin/hv" setup
  [[ "$output" != *"ran-alpha"* ]]
  [[ "$output" == *"ran-beta"* ]]
}

@test "hv setup is idempotent" {
  "$HV_ROOT/bin/hv" setup
  run "$HV_ROOT/bin/hv" setup
  [[ "$output" != *"ran-alpha"* ]]
  [[ "$output" != *"ran-beta"* ]]
}

@test "hv check never mutates and exits 1 when drifted" {
  run "$HV_ROOT/bin/hv" check
  [ "$status" -eq 1 ]
  [ ! -f "$HOME/alpha.done" ]
}

@test "hv check exits 0 when everything is converged" {
  touch "$HOME/alpha.done" "$HOME/beta.done"
  run "$HV_ROOT/bin/hv" check
  [ "$status" -eq 0 ]
}

@test "hv setup --only runs the named step and no others" {
  run "$HV_ROOT/bin/hv" setup --only beta
  [[ "$output" == *"ran-beta"* ]]
  [[ "$output" != *"ran-alpha"* ]]
}

@test "hv setup --only forces a converged step to run again" {
  touch "$HOME/beta.done"
  run "$HV_ROOT/bin/hv" setup --only beta
  [[ "$output" == *"ran-beta"* ]]
}

@test "hv setup --only rejects an unknown step name" {
  run "$HV_ROOT/bin/hv" setup --only nope
  [ "$status" -eq 1 ]
  [[ "$stderr$output" == *"unknown step"* ]]
}

@test "hv setup --dry-run mutates nothing" {
  run "$HV_ROOT/bin/hv" setup --dry-run
  [ ! -f "$HOME/alpha.done" ]
}

@test "step variables do not leak between steps" {
  cat > "$HV_STEPS_DIR/30-gamma.sh" <<'STEP'
HV_STEP_NAME="gamma"
HV_STEP_SCOPE="user"
hv_step_check() { return 1; }
hv_step_run() { echo "scope=$HV_STEP_SCOPE"; }
STEP
  run "$HV_ROOT/bin/hv" setup --only gamma
  [[ "$output" == *"scope=user"* ]]
}

@test "hv with no arguments prints usage and exits nonzero" {
  run "$HV_ROOT/bin/hv"
  [ "$status" -ne 0 ]
  [[ "$stderr$output" == *"usage"* ]]
}
