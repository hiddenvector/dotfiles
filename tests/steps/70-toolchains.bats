#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  hv::config_set HV_MODULES "core web python"
  hv::config_load
  # Don't stub by default - individual tests will stub what they need
}

@test "run installs Node LTS and sets it as the default" {
  hv_stub fnm 0 ""
  hv_stub npm 0 ""
  hv_stub pyenv 0 ""
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  hv_assert_called "install --lts"
  hv_assert_called "default lts-latest"
}

@test "run installs the npm globals" {
  hv_stub fnm 0 ""
  hv_stub npm 0 ""
  hv_stub pyenv 0 ""
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  hv_assert_called "pnpm"
  hv_assert_called "vercel"
}

@test "run skips Node entirely without the web module" {
  hv_stub fnm 0 ""
  hv_stub npm 0 ""
  hv_stub pyenv 0 ""
  hv::config_set HV_MODULES "core python"
  hv::config_load
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  hv_assert_not_called "install --lts"
}

@test "run skips Python without the python module" {
  hv_stub fnm 0 ""
  hv_stub npm 0 ""
  hv_stub pyenv 0 ""
  hv::config_set HV_MODULES "core web"
  hv::config_load
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  hv_assert_not_called "pyenv"
}

@test "run does not install Node through Homebrew" {
  hv_stub fnm 0 ""
  hv_stub npm 0 ""
  hv_stub pyenv 0 ""
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  hv_assert_not_called "brew install node"
}

@test "step scope is user" {
  hv_stub fnm 0 ""
  hv_stub npm 0 ""
  hv_stub pyenv 0 ""
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}

@test "dry run installs nothing and claims nothing" {
  hv_stub fnm 0 ""
  hv_stub npm 0 ""
  hv_stub pyenv 0 ""
  HV_DRY_RUN=1
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  hv_assert_not_called "install --lts"
  hv_assert_not_called "default lts-latest"
  hv_assert_not_called "npm install"
  hv_assert_not_called "pyenv install"
  case "$output" in *"✓"*) return 1 ;; esac
}

@test "failed fnm install warns instead of claiming success" {
  hv_stub fnm 1 ""
  hv_stub npm 0 ""
  hv_stub pyenv 0 ""
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  case "$stderr$output" in *"failed"* | *"⚠"*) : ;; *) return 1 ;; esac
  case "$output" in *"✓ Node"*) return 1 ;; esac
}

@test "failed npm install warns instead of claiming success" {
  hv_stub fnm 0 ""
  hv_stub npm 1 ""
  hv_stub pyenv 0 ""
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  case "$stderr$output" in *"failed"* | *"⚠"*) : ;; *) return 1 ;; esac
  case "$output" in *"✓ Node"*) return 1 ;; esac
}

@test "failed pyenv install warns instead of claiming success" {
  hv_stub fnm 0 ""
  hv_stub npm 0 ""
  hv_stub pyenv 1 ""
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  case "$stderr$output" in *"failed"* | *"⚠"*) : ;; *) return 1 ;; esac
  case "$output" in *"✓ Python"*) return 1 ;; esac
}

@test "a failed toolchain install still returns 0 so later steps run" {
  hv_stub fnm 1 ""
  hv_stub npm 0 ""
  hv_stub pyenv 0 ""
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
}

@test "check passes when both fnm and pyenv are available with correct versions" {
  hv_stub fnm 0 "v22.0.0"
  hv_stub pyenv 0 ""
  # Mock fnm list to show lts-latest alias
  cat > "$HV_STUB_DIR/fnm_list" <<'FNMLIST'
#!/usr/bin/env bash
echo "* v24.16.0 default, lts-latest"
echo "* system"
FNMLIST
  chmod +x "$HV_STUB_DIR/fnm_list"

  # Override fnm to handle "list" subcommand
  cat > "$HV_STUB_DIR/fnm" <<'FNM'
#!/usr/bin/env bash
echo "fnm $*" >> "$HV_STUB_LOG"
case "$1" in
  current) printf 'v24.16.0\n' ;;
  list) sed 's/^/fnm list /' <<'END'
* v24.16.0 default, lts-latest
* system
END
       ;;
  *) exit 0 ;;
esac
FNM
  chmod +x "$HV_STUB_DIR/fnm"

  # Mock pyenv version-name
  cat > "$HV_STUB_DIR/pyenv" <<'PYENV'
#!/usr/bin/env bash
echo "pyenv $*" >> "$HV_STUB_LOG"
case "$1" in
  version-name) printf '3.13.13\n' ;;
  *) exit 0 ;;
esac
PYENV
  chmod +x "$HV_STUB_DIR/pyenv"

  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "check fails when fnm is missing with web module" {
  hv_stub pyenv 0 ""
  # Remove fnm stub to simulate missing fnm
  rm "$HV_STUB_DIR/fnm"
  hv::config_set HV_MODULES "core web"
  hv::config_load
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check fails when fnm current fails" {
  hv_stub fnm 1 ""
  hv_stub pyenv 0 ""
  hv::config_set HV_MODULES "core web"
  hv::config_load
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check fails when lts-latest alias is absent" {
  # Stub fnm to have current but no lts-latest in list output
  cat > "$HV_STUB_DIR/fnm" <<'FNM'
#!/usr/bin/env bash
echo "fnm $*" >> "$HV_STUB_LOG"
case "$1" in
  current) printf 'v22.0.0\n' ;;
  list) printf '* v22.0.0 default\n* system\n' ;;
  *) exit 0 ;;
esac
FNM
  chmod +x "$HV_STUB_DIR/fnm"
  hv_stub pyenv 0 ""
  hv::config_set HV_MODULES "core web"
  hv::config_load
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check fails when pyenv version is not 3.13" {
  hv_stub fnm 0 "v24.16.0"
  # Mock fnm list with lts-latest
  cat > "$HV_STUB_DIR/fnm" <<'FNM'
#!/usr/bin/env bash
echo "fnm $*" >> "$HV_STUB_LOG"
case "$1" in
  current) printf 'v24.16.0\n' ;;
  list) printf '* v24.16.0 default, lts-latest\n* system\n' ;;
  *) exit 0 ;;
esac
FNM
  chmod +x "$HV_STUB_DIR/fnm"

  # Mock pyenv to report wrong version
  cat > "$HV_STUB_DIR/pyenv" <<'PYENV'
#!/usr/bin/env bash
echo "pyenv $*" >> "$HV_STUB_LOG"
case "$1" in
  version-name) printf '3.9.0\n' ;;
  *) exit 0 ;;
esac
PYENV
  chmod +x "$HV_STUB_DIR/pyenv"

  hv::config_set HV_MODULES "core python"
  hv::config_load
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}
