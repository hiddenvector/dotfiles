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
  # `[ ]`/`case`, not `[[ ]]`, for every non-final check: bash 3.2's `set -e`
  # does not reliably abort on a failing `[[ ]]` unless it is the function's
  # last statement.
  case "$output" in
    *ran-alpha*) : ;;
    *) return 1 ;;
  esac
  case "$output" in
    *ran-beta*) : ;;
    *) return 1 ;;
  esac
  [[ "${output%%ran-beta*}" == *"ran-alpha"* ]]
}

@test "hv setup skips steps that are already converged" {
  touch "$HOME/alpha.done"
  run "$HV_ROOT/bin/hv" setup
  # See the comment above re: bash 3.2 and non-final `[[ ]]`.
  case "$output" in
    *ran-alpha*) return 1 ;;
  esac
  [[ "$output" == *"ran-beta"* ]]
}

@test "hv setup is idempotent" {
  "$HV_ROOT/bin/hv" setup
  run "$HV_ROOT/bin/hv" setup
  # See the comment above re: bash 3.2 and non-final `[[ ]]`.
  case "$output" in
    *ran-alpha*) return 1 ;;
  esac
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
  # See the comment on "hv setup runs every drifted step..." re: bash 3.2
  # and non-final `[[ ]]`.
  case "$output" in
    *ran-beta*) : ;;
    *) return 1 ;;
  esac
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
  # See the comment on "hv setup runs every drifted step..." re: bash 3.2
  # and non-final `[[ ]]`.
  case "$stderr$output" in
    *05-broken*) : ;;
    *) return 1 ;;
  esac
  case "$stderr$output" in
    *"Remaining steps were not run"*) : ;;
    *) return 1 ;;
  esac
  [[ "$output" != *"ran-alpha"* ]]
}

@test "hv setup --only reports the step failed instead of aborting silently" {
  # Before this fix, hv::step_invoke was called here outside any condition
  # context, so a failing hv_step_run tripped `set -e` and exited 1 with no
  # message at all -- the exact same failure the full run already names.
  cat > "$HV_STEPS_DIR/05-broken.sh" <<'STEP'
HV_STEP_NAME="broken"
HV_STEP_SCOPE="user"
hv_step_check() { return 1; }
hv_step_run() { return 3; }
STEP
  run "$HV_ROOT/bin/hv" setup --only broken
  [ "$status" -ne 0 ]
  case "$stderr$output" in
    *"step failed"*) : ;;
    *) return 1 ;;
  esac
  case "$stderr$output" in
    *05-broken*) : ;;
    *) return 1 ;;
  esac
}

@test "a step file that fails to parse is not reported as unknown" {
  # Looked up by the name this file *would* declare if it parsed -- no
  # other step provides that name, so a lookup that merely treats a parse
  # failure as "didn't match" falls through to a false "unknown step: bad".
  echo 'this is ( not valid bash' > "$HV_STEPS_DIR/05-bad.sh"
  run "$HV_ROOT/bin/hv" setup --only bad
  [ "$status" -ne 0 ]
  # See the comment on "hv setup runs every drifted step..." re: bash 3.2
  # and non-final `[[ ]]`.
  case "$stderr$output" in
    *05-bad.sh*) : ;;
    *) return 1 ;;
  esac
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
  # See the comment on "hv setup runs every drifted step..." re: bash 3.2
  # and non-final `[[ ]]`.
  case "$output" in
    *ran-extra*) : ;;
    *) return 1 ;;
  esac
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

@test "hv check runs without unbound-variable errors on a fresh config" {
  # Every other test in this file points HV_STEPS_DIR at a private fixture.
  # This one deliberately runs against the *real* setup/steps directory with
  # a brand-new sandboxed HOME and no config file on disk -- exactly the
  # state hv::config_load exists to handle (HV_MODULES etc. unset until
  # something loads the config), and the state a fresh `git clone` followed
  # by `bin/hv check` actually starts from. A unit test cannot catch a
  # missing hv::config_load call because every .bats setup() calls
  # hv::config_load (or hv::config_set then hv::config_load) itself.
  unset HV_STEPS_DIR
  # Real Homebrew may well be installed on the machine running this test
  # (it is, in dev). Point steps 20 and 50 at a prefix with no brew binary
  # so their checks fail fast and deterministically instead of shelling out
  # to the real thing.
  export HV_BREW_PREFIX="$BATS_TEST_TMPDIR/no-brew"
  run "$HV_ROOT/bin/hv" check
  # hv check is allowed to report drift (exit 1) on a fresh sandbox -- that
  # is expected, not a bug. What it must never do is blow up with a shell
  # runtime error, which is the actual symptom the missing hv::config_load
  # call produced: "HV_MODULES: unbound variable" from inside hv::modules.
  case "$stderr$output" in
    *"unbound variable"*) return 1 ;;
  esac
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "hv setup --dry-run prompts for nothing" {
  # As above, this runs against the *real* setup/steps -- that is where the
  # bug lived: several steps (identity, overlay, homebrew's shared-write
  # offer) reached hv::ask/hv::confirm/hv::confirm_always before checking
  # HV_DRY_RUN, so a preview would stop and interrogate the user for real
  # instead of just describing what it would ask. Every prompt function in
  # setup/lib/prompt.sh prints "<question> [<default>]: " (or "[y/N]: ")
  # to stderr *before* it ever tries to read a line -- so checking for that
  # "]: " marker in the output is EOF-agnostic: it catches the bug even
  # though this sandbox's own stdin is already closed, which is exactly
  # the condition (a `curl | bash` install, or a test harness) that let
  # this bug ship unnoticed in the first place.
  unset HV_STEPS_DIR
  export HV_BREW_PREFIX="$BATS_TEST_TMPDIR/no-brew"
  # These two are read-only inspection commands that real steps call
  # directly (never through hv::run) because they must reflect real machine
  # state even during a preview -- xcode-select -p (00-preflight) and
  # defaults read (60-macos). Stub them so the assertion below can tell a
  # legitimate read apart from a real mutation; every write in these steps
  # already goes through hv::run and is dry-run-safe regardless.
  hv_stub xcode-select 0 ""
  hv_stub defaults 0 "0"
  run "$HV_ROOT/bin/hv" setup --dry-run
  [ "$status" -eq 0 ]
  case "$stderr$output" in
    *"]: "*) return 1 ;;
  esac
  # Belt-and-suspenders: a step that mutated for real under --dry-run would
  # hit one of the sandbox's deny-by-default stubs and be swallowed by the
  # assertions above, which only look for prompt markers. This is the
  # reviewer's highest-value single test change on the branch.
  hv_assert_no_refusals
}

@test "hv setup --dry-run does not block waiting on stdin" {
  # Belt-and-suspenders for the test above: actually connect stdin to a
  # source that never delivers EOF (/dev/zero -- infinite NUL bytes, no
  # newline, ever) and prove the process still finishes. If any step
  # reaches a real `read` (via hv::ask/hv::confirm/hv::confirm_always) this
  # hangs forever instead of completing -- which is the literal bug
  # reported against the previous version of this dry-run path (it blocked
  # for two minutes against a real, non-EOF stdin).
  unset HV_STEPS_DIR
  export HV_BREW_PREFIX="$BATS_TEST_TMPDIR/no-brew"
  # See the comment on the previous test re: xcode-select/defaults being
  # real, read-only inspection calls that legitimately run even under
  # --dry-run.
  hv_stub xcode-select 0 ""
  hv_stub defaults 0 "0"
  local out="$BATS_TEST_TMPDIR/dry-run.out"
  local rc="$BATS_TEST_TMPDIR/dry-run.rc"
  ( "$HV_ROOT/bin/hv" setup --dry-run < /dev/zero > "$out" 2>&1; echo $? > "$rc" ) &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "still running after ${waited}s -- something is blocked reading stdin:" >&2
    cat "$out" >&2
    return 1
  fi
  wait "$pid" 2>/dev/null || true
  [ "$(cat "$rc")" = "0" ]
  # As above: prove nothing hit a deny stub, not just that it exited 0 and
  # printed no prompt marker.
  hv_assert_no_refusals
}

@test "module selection from step 10 reaches a later step in the same hv setup run" {
  # Regression test for: hv::config_load runs exactly once, at bin/hv
  # startup, so it populates HV_MODULES in the *parent* process. The real
  # 10-machine.sh writes the user's module choices to the config FILE from
  # inside its own step subshell (via hv::config_set) -- that never touches
  # this process's already-exported HV_MODULES. Every later step's subshell
  # inherits the parent's environment, so without hv::cmd_setup reloading
  # config between steps, a later step in this SAME `hv setup` invocation
  # would still see the stale startup value ("core") no matter what the
  # user actually picked at step 10 -- exactly the bug where a fresh
  # `hv setup` installs only core, silently.
  #
  # No .bats setup() in this suite can catch this class of bug: every one
  # of them calls hv::config_load (or config_set then config_load) itself,
  # which papers over a missing reload in the real binary. Only driving the
  # real bin/hv end-to-end -- with HV_CONFIG_HOME pointing at a directory
  # that starts with no config file at all -- reproduces it.
  export HV_STEPS_DIR="$BATS_TEST_TMPDIR/module-steps"
  mkdir -p "$HV_STEPS_DIR"
  # The real step, unmodified -- this is what actually writes HV_MODULES.
  cp "$HV_ROOT/setup/steps/10-machine.sh" "$HV_STEPS_DIR/10-machine.sh"

  # A private downstream step standing in for 50-packages.sh / 70-toolchains.sh:
  # it only needs to prove what a later step's subshell sees. hv::modules and
  # HV_ALL_MODULES are inherited from the parent shell's function/variable
  # table into this subshell for free -- no re-sourcing needed, same as for
  # any other step file.
  local marker="$BATS_TEST_TMPDIR/modules-seen"
  export HV_MARKER_FILE="$marker"
  cat > "$HV_STEPS_DIR/50-modcheck.sh" <<'STEP'
HV_STEP_NAME="modcheck"
HV_STEP_SCOPE="user"
hv_step_check() { return 1; }
hv_step_run() { hv::modules | tr '\n' ' ' > "$HV_MARKER_FILE"; }
STEP

  # HV_CONFIG_HOME starts empty -- hv_setup_sandbox never wrote anything to
  # it -- exactly a fresh machine's first run. With no existing config,
  # step 10's per-module confirm defaults every module to "enable", and
  # HV_YES=1 accepts every default without reading stdin: "she answers yes
  # to every module," from the bug report, with no stdin choreography
  # needed to reach it.
  hv_stub sudo 0 ""
  hv_stub scutil 0 "atlas"
  hv_stub profiles 0 "MDM enrollment: No"
  export HV_YES=1

  run "$HV_ROOT/bin/hv" setup
  [ "$status" -eq 0 ]
  hv_assert_no_refusals

  [ -f "$marker" ]
  case "$(cat "$marker")" in
    *swift*) : ;;
    *) return 1 ;;
  esac
  case "$(cat "$marker")" in
    *web*) : ;;
    *) return 1 ;;
  esac
}
