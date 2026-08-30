#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
  hv_stub gh 0 "someuser"
  hv_stub git 0 ""
  export HV_YES=1
}

@test "check passes when an overlay is configured and cloned" {
  mkdir -p "$HOME/overlay"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "check passes when the user explicitly declined" {
  hv::config_set HV_OVERLAY "none"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "check fails when configured but the clone is missing" {
  hv::config_set HV_OVERLAY "$HOME/gone"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check fails when nothing is configured" {
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "run clones a configured overlay that is missing locally" {
  hv::config_set HV_OVERLAY "$HOME/overlay"
  hv::config_set HV_OVERLAY_URL "https://github.com/someuser/dotfiles"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run
  hv_assert_called "clone"
}

@test "run defaults to hv-overlay, not dotfiles, as the overlay repo name" {
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run
  [[ "$output" == *"someuser/hv-overlay"* ]]
  [[ "$output" != *"someuser/dotfiles"* ]]
}

@test "run rejects an existing repo that does not pass the overlay contract check" {
  # The general gh stub (from setup()) returns "someuser" for every
  # invocation, including the tree listing the contract check fetches --
  # which contains none of the overlay markers, so this repo must be
  # rejected rather than offered for adoption.
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run
  [[ "$output" == *"doesn't look like an hv overlay"* ]]
  hv_assert_not_called "clone"
  [ "$(hv::config_get HV_OVERLAY)" != "$HOME/Developer/github.com/someuser/hv-overlay" ]
}

@test "run adopts an existing repo that passes the overlay contract check" {
  cat > "$HV_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
echo "gh \$*" >> "$HV_STUB_LOG"
case "\$1 \$2" in
  "api user") echo someuser; exit 0 ;;
  "repo view") exit 0 ;;
esac
case "\$*" in
  *"defaultBranchRef"*) echo main; exit 0 ;;
  *"git/trees/"*) printf 'brew/personal.Brewfile\nzshrc.d/personal.zsh\n'; exit 0 ;;
esac
exit 0
STUB
  chmod +x "$HV_STUB_DIR/gh"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run bash -c "printf 'y\n' | { export HV_YES=0; source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/config.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; source '$HV_ROOT/setup/steps/35-overlay.sh'; hv_step_run; }"
  hv_assert_called "clone https://github.com/someuser/hv-overlay"
  [[ "$output" == *"someuser/hv-overlay"* ]]
}

@test "run rejects an existing repo that looks like a full dotfiles repo, even under --yes" {
  # A repo that matches an overlay marker (git/config is common to both
  # shapes) but ALSO carries install.sh/bin/hv/a top-level Brewfile must
  # still be rejected -- this is exactly this developer's real
  # hyperspacemark/dotfiles repo shape.
  cat > "$HV_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
echo "gh \$*" >> "$HV_STUB_LOG"
case "\$1 \$2" in
  "api user") echo someuser; exit 0 ;;
  "repo view") exit 0 ;;
esac
case "\$*" in
  *"defaultBranchRef"*) echo main; exit 0 ;;
  *"git/trees/"*) printf 'install.sh\nbin/hv\nBrewfile\ngit/config\n'; exit 0 ;;
esac
exit 0
STUB
  chmod +x "$HV_STUB_DIR/gh"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run
  [[ "$output" == *"doesn't look like an hv overlay"* ]]
  hv_assert_not_called "clone"
}

@test "run never creates a repo under --yes alone" {
  hv_stub gh 1 ""
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run < /dev/null
  hv_assert_not_called "repo create"
}

@test "run creates a private repo by default when confirmed" {
  hv_stub gh 1 ""
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  # Three distinct answers: "y" confirms creation, then two blank lines accept
  # the repo-name and visibility defaults. `yes y` would answer every prompt
  # with "y", including visibility, producing "--y" instead of "--private" --
  # defeating the point of this test, which is that private is the default.
  # HV_YES is forced off here so hv::ask actually reads these answers instead
  # of short-circuiting to its default (as the outer HV_YES=1 would).
  run bash -c "printf 'y\n\n\n' | { export HV_YES=0; source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/config.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; source '$HV_ROOT/setup/steps/35-overlay.sh'; hv_step_run; }"
  hv_assert_called "--private"
}

@test "a failed repo create does not claim success or migrate" {
  mkdir -p "$HV_CONFIG_HOME"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  # gh must fail both `repo view` (so case 2 is skipped and case 3 is
  # reached) and `repo create` (the failure under test), while `api` keeps
  # succeeding so a handle is still resolved.
  cat > "$HV_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
echo "gh \$*" >> "$HV_STUB_LOG"
case "\$1" in
  api) echo someuser; exit 0 ;;
  repo) exit 1 ;;
esac
exit 0
STUB
  chmod +x "$HV_STUB_DIR/gh"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run < <(printf 'y\n')
  # bash 3.2's `set -e` does not reliably abort on a failing `[[ ]]` unless
  # it is the function's last statement (a long-standing bash 3.2 quirk --
  # `[ ]` does not have this problem), so the substring check goes last.
  [ -f "$HV_CONFIG_HOME/local.Brewfile" ]
  hv_assert_not_called "clone"
  [ "$(hv::config_get HV_OVERLAY)" != "$HOME/Developer/github.com/someuser/hv-overlay" ]
  [[ "$stderr$output" != *"✓ created github.com"* ]]
}

@test "a failed clone after a successful create does not scaffold or claim success" {
  mkdir -p "$HV_CONFIG_HOME"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  # `repo view` fails (reach case 3), `repo create` succeeds, then `git
  # clone` fails -- the repo now genuinely exists on GitHub but the local
  # side never got set up.
  cat > "$HV_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
echo "gh \$*" >> "$HV_STUB_LOG"
case "\$1" in
  api) echo someuser; exit 0 ;;
  repo)
    case "\$2" in
      view) exit 1 ;;
      create) exit 0 ;;
    esac ;;
esac
exit 0
STUB
  chmod +x "$HV_STUB_DIR/gh"
  cat > "$HV_STUB_DIR/git" <<STUB
#!/usr/bin/env bash
echo "git \$*" >> "$HV_STUB_LOG"
[ "\$1" = "clone" ] && exit 1
exit 0
STUB
  chmod +x "$HV_STUB_DIR/git"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run < <(printf 'y\n')
  # See the comment in the previous test re: bash 3.2 and non-final `[[ ]]`.
  [ -f "$HV_CONFIG_HOME/local.Brewfile" ]
  [ ! -f "$HOME/Developer/github.com/someuser/hv-overlay/README.md" ]
  # The repo genuinely was created -- the warning is allowed (expected, even)
  # to say so plainly ("created ..., but the local clone failed"). What must
  # never appear is the hv::ok success line itself.
  [[ "$stderr$output" != *"✓ created github.com"* ]]
}

@test "run scaffolds the overlay contract directories" {
  export HV_OVERLAY_DIR="$HOME/overlay"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  hv::_scaffold_overlay "$HV_OVERLAY_DIR"
  [ -f "$HV_OVERLAY_DIR/brew/personal.Brewfile" ]
  [ -f "$HV_OVERLAY_DIR/zshrc.d/personal.zsh" ]
  [ -f "$HV_OVERLAY_DIR/git/config" ]
  [ -f "$HV_OVERLAY_DIR/README.md" ]
}

@test "run migrates existing local config into a new overlay" {
  mkdir -p "$HV_CONFIG_HOME" "$HOME/.zshrc.d" "$HOME/overlay"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  hv::_scaffold_overlay "$HOME/overlay"
  hv::_migrate_local "$HOME/overlay"
  grep -q "chatgpt" "$HOME/overlay/brew/personal.Brewfile"
  [ ! -f "$HV_CONFIG_HOME/local.Brewfile" ]
}

@test "a failed append leaves local.Brewfile in place" {
  mkdir -p "$HV_CONFIG_HOME"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  hv::_scaffold_overlay "$HOME/overlay"
  # A read-only *file* blocks the append (a read-only directory would not --
  # appending to an existing file needs write permission on the file itself,
  # not on the directory that contains it).
  chmod 444 "$HOME/overlay/brew/personal.Brewfile"
  run hv::_migrate_local "$HOME/overlay"
  chmod 644 "$HOME/overlay/brew/personal.Brewfile"
  [ -f "$HV_CONFIG_HOME/local.Brewfile" ]
  [[ "$stderr$output" == *"leaving"* ]]
}

@test "the scaffolded README explains the contract" {
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  hv::_scaffold_overlay "$HOME/overlay"
  grep -q "brew/" "$HOME/overlay/README.md"
  grep -q "zshrc.d/" "$HOME/overlay/README.md"
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
