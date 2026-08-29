#!/usr/bin/env bash
# Sandbox for every test: fake HOME, fake PATH, no real system access.

HV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HV_ROOT

hv_setup_sandbox() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export HV_CONFIG_HOME="$HOME/.config/hv"
  export HV_STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  export HV_STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  export HV_DRY_RUN=0
  export HV_YES=0
  # Capture real git before modifying PATH, so stub cannot recurse into itself.
  local real_git
  real_git="$(command -v git)"
  export HV_REAL_GIT="$real_git"
  mkdir -p "$HOME" "$HV_STUB_DIR"
  : > "$HV_STUB_LOG"
  PATH="$HV_STUB_DIR:$PATH"
  export PATH
  hv_deny_dangerous
}

# Create a fake executable that logs its invocation and returns a fixed code.
hv_stub() {
  local name="$1" code="${2:-0}" out="${3:-}"
  cat > "$HV_STUB_DIR/$name" <<STUB
#!/usr/bin/env bash
echo "$name \$*" >> "$HV_STUB_LOG"
[ -n "$out" ] && printf '%s\n' "$out"
exit $code
STUB
  chmod +x "$HV_STUB_DIR/$name"
}

# Commands that must never reach the real system from a test. Each gets a
# deny stub by default; a test that legitimately needs one calls hv_stub to
# override it. A forgotten stub then fails loudly instead of mutating the
# developer's machine.
HV_DANGEROUS_COMMANDS="sudo scutil defaults killall brew gh git-lfs curl wget
xcode-select bioutil profiles networksetup systemsetup launchctl
fnm npm pnpm pyenv uv code claude pre-commit ssh-keygen"

hv_deny_dangerous() {
  local cmd
  for cmd in $HV_DANGEROUS_COMMANDS; do
    # Skip git — it gets a pass-through stub below
    [ "$cmd" = "git" ] && continue
    cat > "$HV_STUB_DIR/$cmd" <<DENY
#!/usr/bin/env bash
echo "REFUSED: test invoked un-stubbed '$cmd' \$*" >> "$HV_STUB_LOG"
echo "REFUSED: test invoked un-stubbed '$cmd' \$*" >&2
exit 111
DENY
    chmod +x "$HV_STUB_DIR/$cmd"
  done

  # git is special: local repo operations under $BATS_TEST_TMPDIR are safe and
  # several tests rely on them. Only the network subcommands are denied. The
  # subcommand is not necessarily $1 — git's global options come first, and
  # some take a value that must be skipped.
  cat > "$HV_STUB_DIR/git" <<GITDENY
#!/usr/bin/env bash
sub=""
skip=0
for a in "\$@"; do
  if [ "\$skip" = "1" ]; then skip=0; continue; fi
  case "\$a" in
    -C|-c|--git-dir|--work-tree|--namespace|--exec-path) skip=1; continue ;;
    -*) continue ;;
    *) sub="\$a"; break ;;
  esac
done
case "\$sub" in
  clone|push|fetch|pull|remote|submodule)
    echo "REFUSED: test invoked network git \$*" >> "$HV_STUB_LOG"
    echo "REFUSED: test invoked network git \$*" >&2
    exit 111 ;;
esac
exec "$HV_REAL_GIT" "\$@"
GITDENY
  chmod +x "$HV_STUB_DIR/git"
}

# Assert a stubbed command was called with the given argument substring.
hv_assert_called() {
  grep -q -- "$1" "$HV_STUB_LOG"
}

hv_assert_not_called() {
  ! grep -q -- "$1" "$HV_STUB_LOG"
}

# Assert no dangerous commands were invoked un-stubbed in this test.
hv_assert_no_refusals() {
  ! grep -q '^REFUSED:' "$HV_STUB_LOG"
}
