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
  mkdir -p "$HOME" "$HV_STUB_DIR"
  : > "$HV_STUB_LOG"
  PATH="$HV_STUB_DIR:$PATH"
  export PATH
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

# Assert a stubbed command was called with the given argument substring.
hv_assert_called() {
  grep -q -- "$1" "$HV_STUB_LOG"
}

hv_assert_not_called() {
  ! grep -q -- "$1" "$HV_STUB_LOG"
}
