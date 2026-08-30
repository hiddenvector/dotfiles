#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  export HV_BREW_PREFIX="$BATS_TEST_TMPDIR/homebrew"
  mkdir -p "$HV_BREW_PREFIX/bin"
  cat > "$HV_BREW_PREFIX/bin/brew" <<'B'
#!/usr/bin/env bash
echo "brew $*" >> "$HV_STUB_LOG"
B
  chmod +x "$HV_BREW_PREFIX/bin/brew"
  hv_stub code 0 ""
  hv::config_set HV_MODULES "core web apps"
  hv::config_load
}

@test "run bundles only the enabled modules" {
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  hv_assert_called "web.Brewfile"
  hv_assert_not_called "swift.Brewfile"
}

@test "run bundles the overlay Brewfiles when an overlay exists" {
  mkdir -p "$HOME/overlay/brew"
  echo 'brew "jq"' > "$HOME/overlay/brew/personal.Brewfile"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  hv::config_load
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  hv_assert_called "personal.Brewfile"
}

@test "run installs VS Code extensions when unrestricted" {
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  hv_assert_called "install-extension"
}

@test "run prints extensions instead of installing them when restricted" {
  hv::config_set HV_RESTRICTED "1"
  hv::config_load
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  hv_assert_not_called "install-extension"
  [[ "$stderr$output" == *"by hand"* ]]
}

@test "run skips extensions entirely without the apps module" {
  hv::config_set HV_MODULES "core"
  hv::config_load
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  hv_assert_not_called "install-extension"
}

@test "every module names a Brewfile that exists" {
  for m in core swift web python security apps; do
    [ -f "$HV_ROOT/brew/$m.Brewfile" ]
  done
}

@test "the web module covers the client repos' tooling" {
  grep -q "fnm" "$HV_ROOT/brew/web.Brewfile"
  grep -q "supabase" "$HV_ROOT/brew/web.Brewfile"
  grep -q "railway" "$HV_ROOT/brew/web.Brewfile"
}

@test "the security module covers the-house's pre-commit requirement" {
  grep -q "gitleaks" "$HV_ROOT/brew/security.Brewfile"
  grep -q "pre-commit" "$HV_ROOT/brew/security.Brewfile"
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/50-packages.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}

@test "a failed module bundle warns instead of claiming success" {
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" brew 1 ""
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  case "$stderr$output" in *"failed"*) : ;; *) return 1 ;; esac
  case "$output" in *"✓ web"*) return 1 ;; esac
}

@test "dry run installs nothing and claims nothing" {
  HV_DRY_RUN=1
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  hv_assert_not_called "bundle --file"
  hv_assert_not_called "install-extension"
  case "$output" in *"✓"*) return 1 ;; esac
}

@test "a failed bundle still returns 0 so later steps run" {
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" brew 1 ""
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
}
