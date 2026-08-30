#!/usr/bin/env bats

load helper

@test "bootstrap duplicates no converge step" {
  ! grep -qE 'pam_tid|brew bundle|scutil --set' "$HV_ROOT/bootstrap"
}

@test "bootstrap execs hv setup" {
  grep -q 'exec .*hv.* setup' "$HV_ROOT/bootstrap"
}

@test "bootstrap clones to the conventional path" {
  grep -q 'Developer/github.com/hiddenvector/dotfiles' "$HV_ROOT/bootstrap"
}

@test "bootstrap is idempotent when the clone already exists" {
  grep -q 'git -C .* pull' "$HV_ROOT/bootstrap"
}

@test "bootstrap passes shellcheck" {
  run shellcheck "$HV_ROOT/bootstrap"
  [ "$status" -eq 0 ]
}

@test "README documents reading bootstrap before running it" {
  grep -qi "read it first" "$HV_ROOT/README.md"
}

@test "bootstrap reconnects stdin to the tty for a piped install" {
  grep -q '/dev/tty' "$HV_ROOT/bootstrap"
}

# Under `curl … | bash`, stdin is the piped script itself and is at EOF by
# the time `hv setup` inherits it -- every prompt would then silently take
# its default with no indication that happened. These two tests exercise
# the fallback for when there is no controlling terminal to reconnect to
# (CI, a container): bootstrap must refuse outright unless the caller was
# explicit with --yes, rather than silently defaulting everything.
#
# Both tests probe /dev/tty from the test process itself first: this
# harness (and CI, macos-latest, non-interactive) has no controlling
# terminal, so the probe fails and the no-tty path below is exercised for
# real. An interactive `bats` run from a real terminal would have one, in
# which case bootstrap would reconnect instead of refusing -- these tests
# skip rather than fail in that environment, since the no-tty path can't be
# exercised there.
@test "bootstrap requires --yes when there is no controlling terminal" {
  if (exec < /dev/tty) 2>/dev/null; then
    skip "this shell has a controlling terminal; cannot exercise the no-tty path"
  fi
  hv_setup_sandbox
  local dest="$HOME/Developer/github.com/hiddenvector/dotfiles"
  mkdir -p "$dest/.git" "$dest/bin"
  hv_stub xcode-select 0 "/Library/Developer/CommandLineTools"
  hv_stub git 0 ""
  cat > "$dest/bin/hv" <<'HV'
#!/usr/bin/env bash
echo "hv-invoked $*"
HV
  chmod +x "$dest/bin/hv"
  run bash -c "'$HV_ROOT/bootstrap' < /dev/null"
  [ "$status" -ne 0 ]
  case "$stderr$output" in
    *"--yes"*) : ;;
    *) return 1 ;;
  esac
  case "$stderr$output" in
    *"hv-invoked"*) return 1 ;;
    *) : ;;
  esac
}

@test "bootstrap proceeds without a terminal when --yes is given" {
  if (exec < /dev/tty) 2>/dev/null; then
    skip "this shell has a controlling terminal; cannot exercise the no-tty path"
  fi
  hv_setup_sandbox
  local dest="$HOME/Developer/github.com/hiddenvector/dotfiles"
  mkdir -p "$dest/.git" "$dest/bin"
  hv_stub xcode-select 0 "/Library/Developer/CommandLineTools"
  hv_stub git 0 ""
  cat > "$dest/bin/hv" <<'HV'
#!/usr/bin/env bash
echo "hv-invoked $*"
HV
  chmod +x "$dest/bin/hv"
  run bash -c "'$HV_ROOT/bootstrap' --yes < /dev/null"
  [ "$status" -eq 0 ]
  case "$stderr$output" in
    *"hv-invoked setup --yes"*) : ;;
    *) return 1 ;;
  esac
}
