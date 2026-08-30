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
hv_step_run() { echo ran-alpha; hv::run touch "$HOME/alpha.done"; }
STEP
  cat > "$HV_STEPS_DIR/20-beta.sh" <<'STEP'
HV_STEP_NAME="beta"
HV_STEP_SCOPE="system"
hv_step_check() { [ -f "$HOME/beta.done" ]; }
hv_step_run() { echo ran-beta; hv::run touch "$HOME/beta.done"; }
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

@test "hv setup --dry-run previews the commands, not just the step names" {
  run "$HV_ROOT/bin/hv" setup --dry-run
  [ ! -f "$HOME/alpha.done" ]
  [[ "$output" == *"would run: touch"* ]]
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

@test "hv setup reports which step failed and that the rest were skipped" {
  cat > "$HV_STEPS_DIR/05-broken.sh" <<'STEP'
HV_STEP_NAME="broken"
HV_STEP_SCOPE="user"
hv_step_check() { return 1; }
hv_step_run() { return 3; }
STEP
  run "$HV_ROOT/bin/hv" setup
  [ "$status" -ne 0 ]
  [[ "$stderr$output" == *"05-broken"* ]]
  [[ "$stderr$output" == *"Remaining steps were not run"* ]]
  [[ "$output" != *"ran-alpha"* ]]
}

@test "a step file that fails to parse is not reported as unknown" {
  # Looked up by the name this file *would* declare if it parsed -- no
  # other step provides that name, so a lookup that merely treats a parse
  # failure as "didn't match" falls through to a false "unknown step: bad".
  echo 'this is ( not valid bash' > "$HV_STEPS_DIR/05-bad.sh"
  run "$HV_ROOT/bin/hv" setup --only bad
  [ "$status" -ne 0 ]
  [[ "$stderr$output" == *"05-bad.sh"* ]]
  [[ "$stderr$output" != *"unknown step: bad"* ]]
}

@test "hv setup runs overlay steps after the base steps" {
  mkdir -p "$HOME/overlay/steps"
  cat > "$HOME/overlay/steps/50-extra.sh" <<'STEP'
HV_STEP_NAME="extra"
HV_STEP_SCOPE="user"
hv_step_check() { return 1; }
hv_step_run() { echo ran-extra; }
STEP
  mkdir -p "$HV_CONFIG_HOME"
  printf 'HV_OVERLAY="%s"
' "$HOME/overlay" > "$HV_CONFIG_HOME/config"
  run "$HV_ROOT/bin/hv" setup
  [[ "$output" == *"ran-extra"* ]]
  [[ "${output%%ran-extra*}" == *"ran-beta"* ]]
}

@test "hv setup tolerates an overlay with no steps directory" {
  mkdir -p "$HOME/overlay" "$HV_CONFIG_HOME"
  printf 'HV_OVERLAY="%s"
' "$HOME/overlay" > "$HV_CONFIG_HOME/config"
  run "$HV_ROOT/bin/hv" setup
  [ "$status" -eq 0 ]
}

@test "hv overlay runs the overlay step" {
  cat > "$HV_STEPS_DIR/35-overlay.sh" <<'STEP'
HV_STEP_NAME="overlay"
HV_STEP_SCOPE="user"
hv_step_check() { return 1; }
hv_step_run() { echo ran-overlay; }
STEP
  run "$HV_ROOT/bin/hv" overlay
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran-overlay"* ]]
}

@test "hv overlay init is equivalent to hv overlay" {
  cat > "$HV_STEPS_DIR/35-overlay.sh" <<'STEP'
HV_STEP_NAME="overlay"
HV_STEP_SCOPE="user"
hv_step_check() { return 1; }
hv_step_run() { echo ran-overlay; }
STEP
  run "$HV_ROOT/bin/hv" overlay init
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran-overlay"* ]]
}

@test "hv overlay rejects an unknown subcommand" {
  run "$HV_ROOT/bin/hv" overlay bogus
  [ "$status" -ne 0 ]
  [[ "$stderr$output" == *"unknown overlay subcommand"* ]]
}

@test "hv overlay --only rejects the combination instead of silently dropping it" {
  run "$HV_ROOT/bin/hv" overlay --only beta
  # Deliberately `[ ]`, not `[[ ]]`, for the substring checks: bash 3.2's
  # `set -e` does not reliably abort on a failing `[[ ]]` unless it is the
  # function's last statement, so a non-final `[[ ]]` here would silently
  # stop enforcing anything and this test would pass even without the fix
  # (confirmed by reverting the fix locally and re-running this test).
  [ "$status" -ne 0 ]
  [ "$output" != "${output/--only/}" ]
  [ "$output" = "${output/ran-beta/}" ]
}
