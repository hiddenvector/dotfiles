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
  case "$output" in *"✓ npm globals"*) return 1 ;; esac
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

@test "check passes when both fnm and pyenv are available" {
  hv_stub fnm 0 "v22.0.0"
  hv_stub pyenv 0 ""
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}
