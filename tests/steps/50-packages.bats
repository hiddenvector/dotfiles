#!/usr/bin/env bats

load ../helper

# Stub `brew` for the untrusted-tap scenario: `bundle --file .../web.Brewfile`
# fails once with Homebrew 6.0.20's real refusal text (captured against a
# real machine where supabase/tap is genuinely untrusted), `brew trust`
# succeeds, and a second bundle attempt (the retry) succeeds. Everything
# else is a no-op success. $HV_STUB_LOG and $HV_STUB_DIR are real exported
# environment variables by the time this stub runs, so the quoted heredoc
# (no interpolation at creation time) picks them up at runtime, same as the
# default brew stub in setup() below.
hv_stub_brew_untrusted_tap() {
  cat > "$HV_BREW_PREFIX/bin/brew" <<'B'
#!/usr/bin/env bash
echo "brew $*" >> "$HV_STUB_LOG"
case "$*" in
  "bundle --file "*web.Brewfile)
    count_file="$HV_STUB_DIR/web_bundle_count"
    n=0
    [ -f "$count_file" ] && n=$(cat "$count_file")
    n=$((n + 1))
    echo "$n" > "$count_file"
    if [ "$n" -eq 1 ]; then
      echo "==> Downloading Homebrew API data" >&2
      echo "Error: Refusing to load formula supabase/tap/supabase from untrusted tap supabase/tap." >&2
      echo 'Run `brew trust --formula supabase/tap/supabase` or `brew trust supabase/tap` to trust it.' >&2
      exit 1
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
B
  chmod +x "$HV_BREW_PREFIX/bin/brew"
}

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
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

@test "run bundles a non-empty local.Brewfile" {
  mkdir -p "$HV_CONFIG_HOME"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  hv_assert_called "local.Brewfile"
}

@test "run does not bundle an empty local.Brewfile" {
  mkdir -p "$HV_CONFIG_HOME"
  : > "$HV_CONFIG_HOME/local.Brewfile"
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  hv_assert_not_called "local.Brewfile"
}

@test "run bundles the comment-only local.Brewfile stub step 40 creates (harmless no-op)" {
  mkdir -p "$HV_CONFIG_HOME"
  echo '# cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  hv_assert_called "local.Brewfile"
}

@test "a failed local bundle warns instead of claiming success" {
  mkdir -p "$HV_CONFIG_HOME"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" brew 1 ""
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  case "$stderr$output" in *"local packages failed"*) : ;; *) return 1 ;; esac
  case "$output" in *"✓ local"*) return 1 ;; esac
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

@test "an untrusted-tap failure states the risk plainly before offering to trust" {
  hv::config_set HV_MODULES "web"
  hv::config_load
  hv_stub_brew_untrusted_tap
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run < /dev/null
  case "$stderr$output" in
    *"untrusted tap 'supabase/tap'"*) : ;;
    *) return 1 ;;
  esac
  case "$stderr$output" in
    *"arbitrary code at install time"*) : ;;
    *) return 1 ;;
  esac
}

@test "declining leaves the tap untrusted, names the manual command, and still returns 0" {
  hv::config_set HV_MODULES "web"
  hv::config_load
  hv_stub_brew_untrusted_tap
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run < /dev/null
  [ "$status" -eq 0 ]
  hv_assert_not_called "trust"
  case "$stderr$output" in
    *"Run 'brew trust supabase/tap' later"*) : ;;
    *) return 1 ;;
  esac
  case "$stderr$output" in
    *"web packages failed"*) : ;;
    *) return 1 ;;
  esac
}

@test "accepting trusts the tap, retries once, and succeeds" {
  hv::config_set HV_MODULES "web"
  hv::config_load
  hv_stub_brew_untrusted_tap
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run <<< "y"
  [ "$status" -eq 0 ]
  hv_assert_called "brew trust supabase/tap"
  case "$stderr$output" in
    *"✓ trusted supabase/tap"*) : ;;
    *) return 1 ;;
  esac
  case "$stderr$output" in
    *"✓ web"*) : ;;
    *) return 1 ;;
  esac
  [ "$(cat "$HV_STUB_DIR/web_bundle_count")" -eq 2 ]
}

@test "a bundle failure with no untrusted-tap wording falls back to the generic message" {
  hv_stub_at_path "$HV_BREW_PREFIX/bin/brew" brew 1 ""
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv_step_run < /dev/null
  [ "$status" -eq 0 ]
  hv_assert_not_called "trust"
  case "$stderr$output" in
    *"would prompt to trust"*) return 1 ;;
    *) : ;;
  esac
}

@test "hv::_untrusted_tap extracts the tap name from Homebrew's real wording" {
  source "$HV_ROOT/setup/steps/50-packages.sh"
  result="$(hv::_untrusted_tap 'Error: Refusing to load formula supabase/tap/supabase from untrusted tap supabase/tap.
Run `brew trust --formula supabase/tap/supabase` or `brew trust supabase/tap` to trust it.')"
  [ "$result" = "supabase/tap" ]
}

@test "hv::_untrusted_tap prints nothing when the wording does not match" {
  source "$HV_ROOT/setup/steps/50-packages.sh"
  result="$(hv::_untrusted_tap 'Error: something unrelated went wrong')"
  [ -z "$result" ]
}

@test "hv::_offer_trust_tap does not prompt or trust under dry run" {
  export HV_DRY_RUN=1
  source "$HV_ROOT/setup/steps/50-packages.sh"
  run hv::_offer_trust_tap "supabase/tap" < /dev/zero
  [ "$status" -eq 1 ]
  case "$output" in
    *"would prompt to trust"*) : ;;
    *) return 1 ;;
  esac
  hv_assert_not_called "trust"
}
