# Hidden Vector dotfiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `github.com/hiddenvector/dotfiles` — a convergent, re-runnable macOS environment installer that any member of the org can clone and use without editing a tracked file.

**Architecture:** A tracked repo holds shared config; per-user preferences live in `~/.config/hv/config`; machine facts are derived from the system rather than stored. A single `hv` entrypoint runs numbered step scripts, each of which exposes `hv_step_check` (report only) and `hv_step_run` (converge). `hv check` calls only the former, so drift detection and setup share one implementation. Personal and employer-specific configuration layers in through an overlay repo.

**Tech Stack:** bash 3.2 (macOS system bash), zsh (interactive shell), Homebrew, bats-core (tests), shellcheck (lint), GitHub Actions (CI).

**Spec:** `docs/superpowers/specs/2026-08-29-company-dotfiles-design.md`

## Global Constraints

- **Target platform:** macOS 14 (Sonoma) or later, Apple Silicon (`arm64`). `/etc/pam.d/sudo_local` requires Sonoma+; Homebrew prefix is `/opt/homebrew`.
- **Shell for all scripts:** `#!/usr/bin/env bash` with `set -euo pipefail`. Must run under macOS's system bash 3.2 — **no** associative arrays (`declare -A`), no `${var,,}`, no `mapfile`, no `**` globstar.
- **Namespacing:** every shared function is prefixed `hv::`. Every environment variable is prefixed `HV_`.
- **No step may write outside** `$HOME`, `/opt/homebrew`, `/etc/pam.d/sudo_local`, or the machine-name system domains.
- **Every step is idempotent.** Running `hv setup` twice must produce no changes on the second run.
- **`--dry-run` mutates nothing.** All mutations go through `hv::run`, which is a no-op that echoes under `HV_DRY_RUN=1`.
- **Tests never touch the real `$HOME`** and never invoke real `sudo`, `brew`, `gh`, `scutil`, `defaults` or `profiles`. `tests/helper.bash` redirects `HOME` to `$BATS_TEST_TMPDIR` and prepends a stub directory to `PATH`.
- **Repo visibility:** public. Nothing sensitive may be committed — identity, secrets and employer config all live outside the repo by design.
- **Modules:** `core swift web python security apps`. `core` is always installed.
- **Step scopes:** `system` (Touch ID, machine name, Homebrew prefix) or `user` (everything else). A second macOS account runs `user` steps fully and `system` steps in verify-only mode.
- **Commit style:** conventional commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).

---

## File Structure

**Foundation**
- `setup/lib/log.sh` — output formatting, `hv::run` dry-run gate, exit codes
- `setup/lib/link.sh` — idempotent symlinking with backup of pre-existing files
- `setup/lib/machine.sh` — derived machine facts (name, MDM, admin, arch, Touch ID sensor)
- `setup/lib/config.sh` — read/write `~/.config/hv/config`, module resolution
- `setup/lib/prompt.sh` — prompts with defaults, `--yes` handling
- `bin/hv` — subcommand dispatcher and step runner

**Steps** (each defines `HV_STEP_NAME`, `HV_STEP_SCOPE`, `hv_step_check`, `hv_step_run`)
- `setup/steps/00-preflight.sh` … `setup/steps/90-check.sh`

**Payload**
- `brew/{core,swift,web,python,security,apps}.Brewfile`
- `git/{gitconfig,gitignore_global,allowed-signers.hv}`
- `zsh/{.zprofile,.zshrc,.zshrc.d/*.zsh}` — interactive helpers only
- `bin/{gprune,gbd}` — non-interactive helpers, callable by agents and CI
- `config/starship.toml`
- `claude/{CLAUDE.md,settings.json,skills/hv-toolbelt/SKILL.md}`

**Docs**
- `docs/usage/{core,swift,web,python,security}.md` — single source of truth
- `docs/{USAGE.md,START-HERE.md,ONBOARDING.md,AGENTS.md}`

**Tests**
- `tests/helper.bash` — sandboxed `HOME`, `PATH` stubs, assertion helpers
- `tests/lib/*.bats`, `tests/steps/*.bats`, `tests/docs/*.bats`

**Entry**
- `bootstrap` — CLT, clone, `exec hv setup`
- `.github/workflows/ci.yml` — shellcheck + bats

---

## Task 1: Test harness and logging

**Files:**
- Create: `tests/helper.bash`
- Create: `setup/lib/log.sh`
- Test: `tests/lib/log.bats`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `hv::log <msg>` — plain line, stdout
  - `hv::ok <msg>` — success line prefixed `✓`
  - `hv::warn <msg>` — warning prefixed `⚠`, **stderr**
  - `hv::err <msg>` — error prefixed `✗`, stderr
  - `hv::run <cmd> [args...]` — executes unless `HV_DRY_RUN=1`, in which case prints `would run: <cmd args>` and returns 0
  - `hv::die <msg>` — `hv::err` then `exit 1`
  - Test helper `hv_stub <name> <exit_code> [stdout]` — creates a fake executable on `PATH` that records its arguments to `$HV_STUB_LOG`

- [ ] **Step 1: Write the failing test**

Create `tests/lib/log.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
}

@test "hv::ok writes a check mark to stdout" {
  run hv::ok "linked"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"linked"* ]]
}

@test "hv::warn writes to stderr, not stdout" {
  run --separate-stderr hv::warn "no sensor"
  [ "$output" = "" ]
  [[ "$stderr" == *"no sensor"* ]]
}

@test "hv::run executes the command when not dry running" {
  HV_DRY_RUN=0
  hv::run touch "$HOME/made-it"
  [ -f "$HOME/made-it" ]
}

@test "hv::run mutates nothing when dry running" {
  HV_DRY_RUN=1
  run hv::run touch "$HOME/made-it"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/made-it" ]
  [[ "$output" == *"would run"* ]]
}

@test "hv::die exits nonzero" {
  run hv::die "boom"
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Write the test helper**

Create `tests/helper.bash`:

```bash
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
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
brew install bats-core shellcheck
bats tests/lib/log.bats
```

Expected: FAIL — `setup/lib/log.sh` does not exist.

- [ ] **Step 4: Write the minimal implementation**

Create `setup/lib/log.sh`:

```bash
#!/usr/bin/env bash
# Output formatting and the dry-run gate. Source, do not execute.

hv::log()  { printf '%s\n' "       $*"; }
hv::ok()   { printf '%s\n' "       ✓ $*"; }
hv::warn() { printf '%s\n' "       ⚠ $*" >&2; }
hv::err()  { printf '%s\n' "       ✗ $*" >&2; }

hv::step() { printf '\n  [%s] %s\n' "$1" "$2"; }

hv::die() { hv::err "$*"; exit 1; }

# Every mutation in this codebase goes through here.
hv::run() {
  if [ "${HV_DRY_RUN:-0}" = "1" ]; then
    hv::log "would run: $*"
    return 0
  fi
  "$@"
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bats tests/lib/log.bats
```

Expected: PASS, 5 tests.

- [ ] **Step 6: Add shellcheck and commit**

```bash
shellcheck setup/lib/log.sh tests/helper.bash
git add tests/helper.bash tests/lib/log.bats setup/lib/log.sh
git commit -m "feat: add test harness and logging library"
```

---

## Task 2: Idempotent symlinking

**Files:**
- Create: `setup/lib/link.sh`
- Test: `tests/lib/link.bats`

**Interfaces:**
- Consumes: `hv::run`, `hv::ok`, `hv::warn` from `setup/lib/log.sh`
- Produces:
  - `hv::linked <src> <dst>` — returns 0 if `dst` is a symlink resolving to `src`, 1 otherwise. Never mutates.
  - `hv::link <src> <dst>` — creates parent dirs, backs up a pre-existing regular file to `<dst>.bak.<epoch>`, then symlinks. Idempotent.

The current `install.sh` calls `exit 1` when it finds a pre-existing regular file, stranding the run halfway. Backing up instead is what makes the installer safe to re-run on a machine that already has hand-written dotfiles.

- [ ] **Step 1: Write the failing test**

Create `tests/lib/link.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/link.sh"
  SRC="$BATS_TEST_TMPDIR/src"
  echo "content" > "$SRC"
}

@test "hv::link creates a symlink" {
  hv::link "$SRC" "$HOME/.zshrc"
  [ -L "$HOME/.zshrc" ]
  [ "$(readlink "$HOME/.zshrc")" = "$SRC" ]
}

@test "hv::link creates missing parent directories" {
  hv::link "$SRC" "$HOME/.config/deep/nested/file"
  [ -L "$HOME/.config/deep/nested/file" ]
}

@test "hv::link is idempotent" {
  hv::link "$SRC" "$HOME/.zshrc"
  hv::link "$SRC" "$HOME/.zshrc"
  [ "$(readlink "$HOME/.zshrc")" = "$SRC" ]
}

@test "hv::link backs up a pre-existing regular file instead of failing" {
  echo "hand written" > "$HOME/.zshrc"
  run hv::link "$SRC" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.zshrc" ]
  ls "$HOME"/.zshrc.bak.* >/dev/null
  grep -q "hand written" "$HOME"/.zshrc.bak.*
}

@test "hv::link retargets a symlink pointing somewhere else" {
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$HOME/.zshrc"
  hv::link "$SRC" "$HOME/.zshrc"
  [ "$(readlink "$HOME/.zshrc")" = "$SRC" ]
}

@test "hv::linked reports true only for a correct link" {
  hv::link "$SRC" "$HOME/.zshrc"
  run hv::linked "$SRC" "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  run hv::linked "$BATS_TEST_TMPDIR/other" "$HOME/.zshrc"
  [ "$status" -eq 1 ]
}

@test "hv::linked reports false for a missing destination" {
  run hv::linked "$SRC" "$HOME/.nope"
  [ "$status" -eq 1 ]
}

@test "hv::link under dry run mutates nothing" {
  HV_DRY_RUN=1
  hv::link "$SRC" "$HOME/.zshrc"
  [ ! -e "$HOME/.zshrc" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/lib/link.bats
```

Expected: FAIL — `setup/lib/link.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `setup/lib/link.sh`:

```bash
#!/usr/bin/env bash
# Idempotent symlinking. Source, do not execute.

# True when dst is already a symlink resolving to src. Never mutates.
hv::linked() {
  local src="$1" dst="$2"
  [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]
}

hv::link() {
  local src="$1" dst="$2"

  if hv::linked "$src" "$dst"; then
    return 0
  fi

  hv::run mkdir -p "$(dirname "$dst")"

  # A real file we did not create: preserve it rather than stranding the run.
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    local backup="$dst.bak.$(date +%s)"
    hv::warn "backing up existing $dst -> $backup"
    hv::run mv "$dst" "$backup"
  fi

  hv::run ln -sfn "$src" "$dst"
  hv::ok "linked $dst"
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bats tests/lib/link.bats
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
shellcheck setup/lib/link.sh
git add setup/lib/link.sh tests/lib/link.bats
git commit -m "feat: add idempotent symlinking with backup"
```

---

## Task 3: Derived machine facts

**Files:**
- Create: `setup/lib/machine.sh`
- Test: `tests/lib/machine.bats`

**Interfaces:**
- Consumes: `setup/lib/log.sh`
- Produces:
  - `hv::machine_name` — echoes `scutil --get ComputerName`, or empty on failure
  - `hv::machine_has_default_name` — 0 when the name still looks like a macOS default (`Marks-MacBook-Pro`, `Mac Studio`, contains an apostrophe-s)
  - `hv::is_managed` — 0 when MDM-enrolled per `profiles status -type enrollment`
  - `hv::is_admin` — 0 when the current user is in the `admin` group
  - `hv::arch` — echoes `uname -m`
  - `hv::has_touchid_sensor` — 0 when `bioutil -r` reports a sensor
  - `hv::suggest_machine_name` — echoes an unused name from the Greek myth list

The spec requires these be **derived, not stored** — two accounts on one Mac must not keep two drifting copies of a fact about the machine.

- [ ] **Step 1: Write the failing test**

Create `tests/lib/machine.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
}

@test "hv::machine_name reads ComputerName from scutil" {
  hv_stub scutil 0 "prometheus"
  run hv::machine_name
  [ "$output" = "prometheus" ]
  hv_assert_called "--get ComputerName"
}

@test "hv::machine_name is empty when scutil fails" {
  hv_stub scutil 1 ""
  run hv::machine_name
  [ "$output" = "" ]
}

@test "hv::machine_has_default_name detects a stock hostname" {
  hv_stub scutil 0 "Marks-MacBook-Pro"
  run hv::machine_has_default_name
  [ "$status" -eq 0 ]
}

@test "hv::machine_has_default_name detects an apostrophe name" {
  hv_stub scutil 0 "Mark's Mac Studio"
  run hv::machine_has_default_name
  [ "$status" -eq 0 ]
}

@test "hv::machine_has_default_name accepts a proper name" {
  hv_stub scutil 0 "prometheus"
  run hv::machine_has_default_name
  [ "$status" -eq 1 ]
}

@test "hv::is_managed is true when enrolled" {
  hv_stub profiles 0 "Enrolled via DEP: Yes"
  run hv::is_managed
  [ "$status" -eq 0 ]
}

@test "hv::is_managed is false when not enrolled" {
  hv_stub profiles 0 "Enrolled via DEP: No
MDM enrollment: No"
  run hv::is_managed
  [ "$status" -eq 1 ]
}

@test "hv::is_admin is true when in the admin group" {
  hv_stub id 0 "staff admin everyone"
  run hv::is_admin
  [ "$status" -eq 0 ]
}

@test "hv::is_admin is false otherwise" {
  hv_stub id 0 "staff everyone"
  run hv::is_admin
  [ "$status" -eq 1 ]
}

@test "hv::has_touchid_sensor is false on hardware without one" {
  hv_stub bioutil 1 ""
  run hv::has_touchid_sensor
  [ "$status" -eq 1 ]
}

@test "hv::suggest_machine_name returns a greek name" {
  hv_stub scutil 0 "Marks-MacBook-Pro"
  run hv::suggest_machine_name
  [ -n "$output" ]
  [[ "$output" =~ ^[a-z]+$ ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/lib/machine.bats
```

Expected: FAIL — `setup/lib/machine.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `setup/lib/machine.sh`:

```bash
#!/usr/bin/env bash
# Machine facts, always derived from the system. Never cached to disk:
# two accounts on one Mac must not hold two drifting copies of one fact.

HV_MACHINE_NAMES="prometheus atlas hestia kalliope hyperion theseus daedalus \
selene orion helios nyx eos"

hv::machine_name() {
  scutil --get ComputerName 2>/dev/null || true
}

# macOS defaults look like "Marks-MacBook-Pro", "Mac Studio", "Mark's MacBook Air".
hv::machine_has_default_name() {
  local name
  name="$(hv::machine_name)"
  [ -z "$name" ] && return 0
  case "$name" in
    *MacBook*|*Mac-Studio*|*"Mac Studio"*|*iMac*|*Mac-mini*|*"Mac mini"*|*"'s "*|*"’s "*)
      return 0 ;;
  esac
  return 1
}

hv::is_managed() {
  profiles status -type enrollment 2>/dev/null | grep -q ': Yes'
}

hv::is_admin() {
  id -Gn 2>/dev/null | tr ' ' '\n' | grep -qx admin
}

hv::arch() { uname -m; }

hv::has_touchid_sensor() {
  bioutil -r >/dev/null 2>&1
}

hv::suggest_machine_name() {
  local current name
  current="$(hv::machine_name)"
  for name in $HV_MACHINE_NAMES; do
    if [ "$name" != "$current" ]; then
      printf '%s\n' "$name"
      return 0
    fi
  done
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bats tests/lib/machine.bats
```

Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
shellcheck setup/lib/machine.sh
git add setup/lib/machine.sh tests/lib/machine.bats
git commit -m "feat: derive machine facts from the system"
```

---

## Task 4: User configuration and module resolution

**Files:**
- Create: `setup/lib/config.sh`
- Test: `tests/lib/config.bats`

**Interfaces:**
- Consumes: `setup/lib/log.sh`
- Produces:
  - `hv::config_file` — echoes `${HV_CONFIG_HOME:-$HOME/.config/hv}/config`
  - `hv::config_load` — sources the file if present; sets `HV_MODULES`, `HV_OVERLAY`, `HV_RESTRICTED` defaults
  - `hv::config_set <KEY> <VALUE>` — idempotent upsert, creating the file if absent
  - `hv::config_get <KEY>` — echoes the value, empty if unset
  - `hv::modules` — echoes resolved modules, one per line, `core` always first, deduplicated
  - `hv::module_enabled <name>` — 0 if enabled

- [ ] **Step 1: Write the failing test**

Create `tests/lib/config.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
}

@test "hv::config_set creates the file and stores a value" {
  hv::config_set HV_MODULES "core web"
  [ -f "$(hv::config_file)" ]
  run hv::config_get HV_MODULES
  [ "$output" = "core web" ]
}

@test "hv::config_set replaces rather than appends" {
  hv::config_set HV_MODULES "core"
  hv::config_set HV_MODULES "core web python"
  run grep -c '^HV_MODULES=' "$(hv::config_file)"
  [ "$output" = "1" ]
  run hv::config_get HV_MODULES
  [ "$output" = "core web python" ]
}

@test "hv::config_get is empty for an unset key" {
  run hv::config_get HV_OVERLAY
  [ "$output" = "" ]
}

@test "hv::config_load defaults modules to core" {
  hv::config_load
  [ "$HV_MODULES" = "core" ]
}

@test "hv::modules always puts core first" {
  hv::config_set HV_MODULES "web core swift"
  hv::config_load
  run hv::modules
  [ "${lines[0]}" = "core" ]
}

@test "hv::modules deduplicates" {
  hv::config_set HV_MODULES "core core web web"
  hv::config_load
  run hv::modules
  [ "${#lines[@]}" -eq 2 ]
}

@test "hv::modules adds core when it was omitted" {
  hv::config_set HV_MODULES "web"
  hv::config_load
  run hv::modules
  [ "${lines[0]}" = "core" ]
  [ "${lines[1]}" = "web" ]
}

@test "hv::module_enabled reflects the config" {
  hv::config_set HV_MODULES "core web"
  hv::config_load
  run hv::module_enabled web
  [ "$status" -eq 0 ]
  run hv::module_enabled swift
  [ "$status" -eq 1 ]
}

@test "config values containing spaces survive a round trip" {
  hv::config_set HV_OVERLAY "/path/with spaces/repo"
  hv::config_load
  [ "$HV_OVERLAY" = "/path/with spaces/repo" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/lib/config.bats
```

Expected: FAIL — `setup/lib/config.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `setup/lib/config.sh`:

```bash
#!/usr/bin/env bash
# Per-user preferences. Machine facts belong in machine.sh, not here.

HV_ALL_MODULES="core swift web python security apps"

hv::config_file() {
  printf '%s\n' "${HV_CONFIG_HOME:-$HOME/.config/hv}/config"
}

hv::config_load() {
  local file
  file="$(hv::config_file)"
  # shellcheck disable=SC1090
  [ -f "$file" ] && . "$file"
  HV_MODULES="${HV_MODULES:-core}"
  HV_OVERLAY="${HV_OVERLAY:-}"
  HV_RESTRICTED="${HV_RESTRICTED:-}"
}

hv::config_get() {
  local key="$1" file
  file="$(hv::config_file)"
  [ -f "$file" ] || return 0
  sed -n "s/^${key}=\"\\(.*\\)\"\$/\\1/p" "$file" | tail -1
}

hv::config_set() {
  local key="$1" value="$2" file tmp
  file="$(hv::config_file)"
  hv::run mkdir -p "$(dirname "$file")"
  [ "${HV_DRY_RUN:-0}" = "1" ] && { hv::log "would set $key"; return 0; }
  [ -f "$file" ] || printf '# Hidden Vector user config. Machine facts are derived, not stored.\n' > "$file"
  tmp="$file.tmp.$$"
  grep -v "^${key}=" "$file" > "$tmp" || true
  printf '%s="%s"\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

# core is mandatory and always first; order otherwise follows HV_ALL_MODULES.
hv::modules() {
  local m
  printf '%s\n' core
  for m in $HV_ALL_MODULES; do
    [ "$m" = "core" ] && continue
    case " $HV_MODULES " in *" $m "*) printf '%s\n' "$m" ;; esac
  done
}

hv::module_enabled() {
  hv::modules | grep -qx "$1"
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bats tests/lib/config.bats
```

Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
shellcheck setup/lib/config.sh
git add setup/lib/config.sh tests/lib/config.bats
git commit -m "feat: add user config store and module resolution"
```

---

## Task 5: Prompts

**Files:**
- Create: `setup/lib/prompt.sh`
- Test: `tests/lib/prompt.bats`

**Interfaces:**
- Consumes: `setup/lib/log.sh`
- Produces:
  - `hv::ask <question> <default>` — echoes the answer; returns the default on empty input or when `HV_YES=1`
  - `hv::confirm <question> <default:y|n>` — 0 for yes; honours `HV_YES=1` as the default
  - `hv::confirm_always <question>` — **ignores `HV_YES`** and always reads from the user. Used for outward-facing actions, per the spec: `gh repo create` must never be triggered by `--yes`.

- [ ] **Step 1: Write the failing test**

Create `tests/lib/prompt.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
}

@test "hv::ask returns typed input" {
  run bash -c "source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo atlas | hv::ask 'Machine name' 'prometheus'"
  [ "$output" = "atlas" ]
}

@test "hv::ask returns the default on empty input" {
  run bash -c "source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo '' | hv::ask 'Machine name' 'prometheus'"
  [ "$output" = "prometheus" ]
}

@test "hv::ask returns the default without reading under --yes" {
  HV_YES=1
  run hv::ask "Machine name" "prometheus"
  [ "$output" = "prometheus" ]
}

@test "hv::confirm accepts y" {
  run bash -c "source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo y | hv::confirm 'Proceed' n"
  [ "$status" -eq 0 ]
}

@test "hv::confirm honours a no default on empty input" {
  run bash -c "source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo '' | hv::confirm 'Proceed' n"
  [ "$status" -eq 1 ]
}

@test "hv::confirm takes the default under --yes" {
  HV_YES=1
  run hv::confirm "Proceed" y
  [ "$status" -eq 0 ]
}

@test "hv::confirm_always ignores --yes and still reads input" {
  run bash -c "export HV_YES=1; source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; echo n | hv::confirm_always 'Create a public repo'"
  [ "$status" -eq 1 ]
}

@test "hv::confirm_always declines when there is no tty and no input" {
  run bash -c "export HV_YES=1; source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; hv::confirm_always 'Create a public repo' < /dev/null"
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/lib/prompt.bats
```

Expected: FAIL — `setup/lib/prompt.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `setup/lib/prompt.sh`:

```bash
#!/usr/bin/env bash
# Prompts. Source, do not execute.

hv::ask() {
  local question="$1" default="$2" answer=""
  if [ "${HV_YES:-0}" = "1" ]; then
    printf '%s\n' "$default"
    return 0
  fi
  printf '       %s [%s]: ' "$question" "$default" >&2
  read -r answer || true
  printf '%s\n' "${answer:-$default}"
}

hv::confirm() {
  local question="$1" default="${2:-n}" answer=""
  if [ "${HV_YES:-0}" = "1" ]; then
    [ "$default" = "y" ]
    return $?
  fi
  local hint="[y/N]"
  [ "$default" = "y" ] && hint="[Y/n]"
  printf '       %s %s: ' "$question" "$hint" >&2
  read -r answer || true
  answer="${answer:-$default}"
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# For outward-facing actions (creating repos, uploading keys). --yes must not
# be able to trigger these; with no input available, decline.
hv::confirm_always() {
  local question="$1" answer=""
  printf '       %s [y/N]: ' "$question" >&2
  read -r answer || return 1
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bats tests/lib/prompt.bats
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
shellcheck setup/lib/prompt.sh
git add setup/lib/prompt.sh tests/lib/prompt.bats
git commit -m "feat: add prompts with --yes handling and an outward-action guard"
```

---

## Task 6: The `hv` dispatcher and step runner

**Files:**
- Create: `bin/hv`
- Test: `tests/bin/hv.bats`

**Interfaces:**
- Consumes: all of `setup/lib/*.sh`
- Produces: the contract every step script must satisfy —

  ```bash
  HV_STEP_NAME="touchid"        # matched by --only
  HV_STEP_SCOPE="system"        # system | user
  hv_step_check() { ... }       # 0 = converged, 1 = drifted. MUST NOT mutate.
  hv_step_run()   { ... }       # converge. May prompt. Must be idempotent.
  ```

  Runner semantics, used by every later task:
  - `hv setup` — for each step in filename order: run `hv_step_check`; skip when clean, otherwise `hv_step_run`.
  - `hv check` — `hv_step_check` only, every step, never mutating. Exit 1 if any step is drifted.
  - `--only <name>` — run just the matching step, forcing `hv_step_run` regardless of check.
  - Each step is sourced in a **subshell**, so `HV_STEP_*` variables cannot leak between steps.

**Design note.** The spec describes system steps running in "verify-only mode" for a second macOS account. Modelling that explicitly would require detecting first-versus-later account, which is fragile. The check-then-run runner gets it for free: on a second account the system state already exists, `hv_step_check` reports clean, and the step is skipped. Where it genuinely is drifted and the account lacks privileges, the step warns rather than dying (enforced per-step in Tasks 7–9). One less concept, same behaviour.

- [ ] **Step 1: Write the failing test**

Create `tests/bin/hv.bats`:

```bash
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
hv_step_run() { echo ran-alpha; touch "$HOME/alpha.done"; }
STEP
  cat > "$HV_STEPS_DIR/20-beta.sh" <<'STEP'
HV_STEP_NAME="beta"
HV_STEP_SCOPE="system"
hv_step_check() { [ -f "$HOME/beta.done" ]; }
hv_step_run() { echo ran-beta; touch "$HOME/beta.done"; }
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/bin/hv.bats
```

Expected: FAIL — `bin/hv` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `bin/hv`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve this script's real location even when symlinked to ~/.local/bin/hv.
_hv_self="${BASH_SOURCE[0]}"
while [ -L "$_hv_self" ]; do
  _hv_dir="$(cd "$(dirname "$_hv_self")" && pwd)"
  _hv_self="$(readlink "$_hv_self")"
  case "$_hv_self" in /*) ;; *) _hv_self="$_hv_dir/$_hv_self" ;; esac
done
HV_ROOT="$(cd "$(dirname "$_hv_self")/.." && pwd)"
export HV_ROOT

HV_STEPS_DIR="${HV_STEPS_DIR:-$HV_ROOT/setup/steps}"

for _lib in log link machine config prompt; do
  # shellcheck disable=SC1090
  . "$HV_ROOT/setup/lib/$_lib.sh"
done

HV_DRY_RUN="${HV_DRY_RUN:-0}"
HV_YES="${HV_YES:-0}"
export HV_DRY_RUN HV_YES

hv::usage() {
  cat >&2 <<'USAGE'
usage: hv <command> [options]

commands:
  setup           converge this machine to the declared state
  check           report drift; mutates nothing; exits 1 if drifted
  update          git pull, then converge
  identity        re-run the identity step
  machine         re-run machine name and module selection
  overlay init    create and wire up a personal overlay repo
  cheatsheet      print usage docs for installed modules

options:
  --only <name>   run only the named step
  --dry-run       print what would change, change nothing
  --yes           accept defaults without prompting
USAGE
}

hv::steps() {
  ls "$HV_STEPS_DIR"/*.sh 2>/dev/null | sort
}

# Echo the file implementing the named step, or nothing.
hv::step_file() {
  local want="$1" f name
  for f in $(hv::steps); do
    name="$(. "$f" >/dev/null 2>&1; printf '%s' "${HV_STEP_NAME:-}")" || true
    name="$(bash -c ". '$f'; printf '%s' \"\$HV_STEP_NAME\"" 2>/dev/null)"
    [ "$name" = "$want" ] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

# Run one step file. mode is "check", "run", or "converge".
hv::step_invoke() {
  local file="$1" mode="$2"
  (
    # shellcheck disable=SC1090
    . "$file"
    case "$mode" in
      check) hv_step_check ;;
      run)   hv_step_run ;;
      converge)
        if hv_step_check >/dev/null 2>&1; then
          exit 0
        fi
        hv_step_run
        ;;
    esac
  )
}

hv::cmd_setup() {
  local only="${1:-}" file
  if [ -n "$only" ]; then
    file="$(hv::step_file "$only")" || hv::die "unknown step: $only"
    hv::step_invoke "$file" run
    return $?
  fi
  for file in $(hv::steps); do
    hv::step_invoke "$file" converge
  done
}

hv::cmd_check() {
  local file drifted=0
  for file in $(hv::steps); do
    hv::step_invoke "$file" check || drifted=1
  done
  return "$drifted"
}

main() {
  local cmd="${1:-}" only=""
  [ $# -gt 0 ] && shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --only) only="${2:-}"; shift 2 ;;
      --dry-run) HV_DRY_RUN=1; export HV_DRY_RUN; shift ;;
      --yes) HV_YES=1; export HV_YES; shift ;;
      *) shift ;;
    esac
  done

  case "$cmd" in
    setup)     hv::cmd_setup "$only" ;;
    check)     hv::cmd_check ;;
    update)    hv::run git -C "$HV_ROOT" pull --ff-only && hv::cmd_setup "" ;;
    identity)  hv::cmd_setup identity ;;
    machine)   hv::cmd_setup machine ;;
    overlay)   hv::cmd_setup overlay ;;
    cheatsheet) hv::cmd_setup cheatsheet ;;
    ""|help|-h|--help) hv::usage; return 1 ;;
    *) hv::err "unknown command: $cmd"; hv::usage; return 1 ;;
  esac
}

main "$@"
```

- [ ] **Step 4: Remove the dead first assignment in `hv::step_file`**

The implementation above contains two assignments to `name`; the first is dead. Delete this line:

```bash
    name="$(. "$f" >/dev/null 2>&1; printf '%s' "${HV_STEP_NAME:-}")" || true
```

Re-run shellcheck to confirm it is clean.

- [ ] **Step 5: Run the test to verify it passes**

```bash
bats tests/bin/hv.bats
```

Expected: PASS, 11 tests.

- [ ] **Step 6: Commit**

```bash
shellcheck bin/hv
chmod +x bin/hv
git add bin/hv tests/bin/hv.bats
git commit -m "feat: add hv dispatcher and check-then-run step runner"
```

---

## Task 7: Step 00 — preflight

**Files:**
- Create: `setup/steps/00-preflight.sh`
- Test: `tests/steps/00-preflight.bats`

**Interfaces:**
- Consumes: `hv::arch`, `hv::is_admin`, `hv::is_managed`, `hv::die`, `hv::warn`, `hv::ok`
- Produces: `HV_STEP_NAME="preflight"`, scope `system`. Fails fast before anything mutates.

Checks, in order: macOS version ≥ 14, arch is `arm64`, Command Line Tools present (installs if not), admin rights (warn only — a non-admin account is supported and simply skips system steps).

- [ ] **Step 1: Write the failing test**

Create `tests/steps/00-preflight.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
  hv_stub sw_vers 0 "26.1"
  hv_stub uname 0 "arm64"
  hv_stub xcode-select 0 "/Library/Developer/CommandLineTools"
  hv_stub id 0 "staff admin"
  hv_stub profiles 0 "MDM enrollment: No"
}

@test "check passes on a supported machine" {
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "check fails when Command Line Tools are absent" {
  hv_stub xcode-select 1 ""
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "run refuses an unsupported macOS version" {
  hv_stub sw_vers 0 "13.6"
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_run
  [ "$status" -ne 0 ]
  [[ "$stderr$output" == *"macOS 14"* ]]
}

@test "run refuses a non-arm64 machine" {
  hv_stub uname 0 "x86_64"
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_run
  [ "$status" -ne 0 ]
  [[ "$stderr$output" == *"arm64"* ]]
}

@test "run installs Command Line Tools when missing" {
  hv_stub xcode-select 1 ""
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_run
  hv_assert_called "xcode-select --install"
}

@test "run warns but does not fail for a non-admin account" {
  hv_stub id 0 "staff everyone"
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  [[ "$stderr$output" == *"admin"* ]]
}

@test "step scope is system" {
  source "$HV_ROOT/setup/steps/00-preflight.sh"
  [ "$HV_STEP_SCOPE" = "system" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/00-preflight.bats
```

Expected: FAIL — `setup/steps/00-preflight.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `setup/steps/00-preflight.sh`:

```bash
#!/usr/bin/env bash
# Fail fast, before anything mutates.

HV_STEP_NAME="preflight"
HV_STEP_SCOPE="system"

hv::_clt_present() { xcode-select -p >/dev/null 2>&1; }

hv::_macos_major() { sw_vers -productVersion 2>/dev/null | cut -d. -f1; }

hv_step_check() {
  hv::_clt_present
}

hv_step_run() {
  hv::step 00 "preflight"

  local major arch
  major="$(hv::_macos_major)"
  [ -n "$major" ] && [ "$major" -ge 14 ] 2>/dev/null \
    || hv::die "requires macOS 14 (Sonoma) or later; found ${major:-unknown}"

  arch="$(hv::arch)"
  [ "$arch" = "arm64" ] \
    || hv::die "requires Apple Silicon (arm64); found $arch"

  hv::ok "macOS $major  $arch"

  if ! hv::_clt_present; then
    hv::log "Command Line Tools missing — installing (GUI prompt)…"
    hv::run xcode-select --install || true
    hv::die "rerun hv setup once Command Line Tools finish installing"
  fi
  hv::ok "Command Line Tools"

  if hv::is_admin; then
    hv::ok "admin rights"
  else
    hv::warn "admin rights: limited — system steps will be skipped"
  fi

  hv::is_managed && hv::warn "this machine is MDM-managed"
  return 0
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bats tests/steps/00-preflight.bats
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
shellcheck -x setup/steps/00-preflight.sh
git add setup/steps/00-preflight.sh tests/steps/00-preflight.bats
git commit -m "feat: add preflight step"
```

---

## Task 8: Step 05 — Touch ID for sudo

**Files:**
- Create: `setup/steps/05-touchid.sh`
- Test: `tests/steps/05-touchid.bats`

**Interfaces:**
- Consumes: `hv::has_touchid_sensor`, `hv::is_managed`, `hv::run`, `hv::warn`, `hv::ok`
- Produces: `HV_STEP_NAME="touchid"`, scope `system`

This runs **second**, before any other step needs `sudo`, so the password is typed exactly once per machine. The spec requires three caveats be surfaced by the tool rather than buried in docs: no built-in sensor on a Mac Studio, MDM blocking the PAM write, and no support over SSH. All three degrade to a warning — never a failure.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/05-touchid.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
  export HV_PAM_FILE="$BATS_TEST_TMPDIR/sudo_local"
  hv_stub bioutil 0 ""
  hv_stub profiles 0 "MDM enrollment: No"
  hv_stub sudo 0 ""
}

@test "check fails when the pam file is absent" {
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check passes when pam_tid is configured" {
  echo "auth       sufficient     pam_tid.so" > "$HV_PAM_FILE"
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "run writes the pam config via sudo tee" {
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  hv_assert_called "tee"
}

@test "run warns and skips when there is no Touch ID sensor" {
  hv_stub bioutil 1 ""
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  [[ "$stderr$output" == *"no Touch ID sensor"* ]]
  hv_assert_not_called "tee"
}

@test "run degrades to a warning when the pam write is blocked" {
  hv_stub sudo 1 ""
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  [[ "$stderr$output" == *"blocked"* ]]
}

@test "run is idempotent" {
  echo "auth       sufficient     pam_tid.so" > "$HV_PAM_FILE"
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  hv_assert_not_called "tee"
}

@test "run mentions the ssh limitation" {
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  run hv_step_run
  [[ "$stderr$output" == *"SSH"* ]]
}

@test "step scope is system" {
  source "$HV_ROOT/setup/steps/05-touchid.sh"
  [ "$HV_STEP_SCOPE" = "system" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/05-touchid.bats
```

Expected: FAIL — `setup/steps/05-touchid.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `setup/steps/05-touchid.sh`:

```bash
#!/usr/bin/env bash
# Runs before every other sudo-requiring step, so the password is typed once.
# /etc/pam.d/sudo_local survives macOS updates; /etc/pam.d/sudo does not.

HV_STEP_NAME="touchid"
HV_STEP_SCOPE="system"

HV_PAM_FILE="${HV_PAM_FILE:-/etc/pam.d/sudo_local}"

hv_step_check() {
  grep -q "pam_tid.so" "$HV_PAM_FILE" 2>/dev/null
}

hv_step_run() {
  hv::step 05 "Touch ID for sudo"

  if hv_step_check; then
    hv::ok "already enabled"
    return 0
  fi

  # A Mac Studio has no built-in sensor: the PAM file would be inert.
  if ! hv::has_touchid_sensor; then
    hv::warn "no Touch ID sensor on this Mac"
    hv::log "Works via a Magic Keyboard with Touch ID. Connect one, then:"
    hv::log "  hv setup --only touchid"
    return 0
  fi

  hv::log "This is the only time you'll type your password."
  if ! echo "auth       sufficient     pam_tid.so" \
      | hv::run sudo tee "$HV_PAM_FILE" >/dev/null 2>&1; then
    hv::warn "blocked — cannot write $HV_PAM_FILE"
    hv::log "Your MDM controls PAM. Continuing with password auth."
    return 0
  fi

  hv::ok "$HV_PAM_FILE written"
  hv::log "Active for sudo in Terminal, iTerm and VS Code."
  hv::log "Not over SSH. tmux needs pam_reattach — see docs/USAGE.md."
  return 0
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bats tests/steps/05-touchid.bats
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
shellcheck -x setup/steps/05-touchid.sh
git add setup/steps/05-touchid.sh tests/steps/05-touchid.bats
git commit -m "feat: enable Touch ID for sudo before any other sudo step"
```

---

## Task 9: Step 10 — machine name and modules

**Files:**
- Create: `setup/steps/10-machine.sh`
- Test: `tests/steps/10-machine.bats`

**Interfaces:**
- Consumes: `hv::machine_name`, `hv::machine_has_default_name`, `hv::suggest_machine_name`, `hv::is_managed`, `hv::config_set`, `hv::ask`, `hv::confirm`
- Produces: `HV_STEP_NAME="machine"`, scope `system`. Writes `HV_MODULES` and `HV_RESTRICTED` to `~/.config/hv/config`.

Overlay configuration is deliberately **not** here — it moved to step 35, because creating or detecting an overlay repo needs `gh` authentication from step 30.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/10-machine.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
  hv_stub scutil 0 "prometheus"
  hv_stub profiles 0 "MDM enrollment: No"
  export HV_YES=1
}

@test "check fails when no config exists" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check passes once modules are recorded" {
  hv::config_set HV_MODULES "core web"
  source "$HV_ROOT/setup/steps/10-machine.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "run leaves an already-named machine alone" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  run hv_step_run
  hv_assert_not_called "--set ComputerName"
}

@test "run renames a machine with a stock name" {
  hv_stub scutil 0 "Marks-MacBook-Pro"
  source "$HV_ROOT/setup/steps/10-machine.sh"
  run hv_step_run
  hv_assert_called "--set ComputerName"
  hv_assert_called "--set HostName"
  hv_assert_called "--set LocalHostName"
}

@test "run records modules to config" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  hv_step_run
  hv::config_load
  [[ "$HV_MODULES" == *"core"* ]]
}

@test "run marks an MDM machine restricted automatically" {
  hv_stub profiles 0 "MDM enrollment: Yes"
  source "$HV_ROOT/setup/steps/10-machine.sh"
  hv_step_run
  run hv::config_get HV_RESTRICTED
  [ "$output" = "1" ]
}

@test "run degrades when scutil is blocked by MDM" {
  hv_stub scutil 1 ""
  source "$HV_ROOT/setup/steps/10-machine.sh"
  run hv_step_run
  [ "$status" -eq 0 ]
  [[ "$stderr$output" == *"blocked"* ]]
}

@test "run is idempotent" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  hv_step_run
  local first; first="$(cat "$(hv::config_file)")"
  hv_step_run
  [ "$first" = "$(cat "$(hv::config_file)")" ]
}

@test "step scope is system" {
  source "$HV_ROOT/setup/steps/10-machine.sh"
  [ "$HV_STEP_SCOPE" = "system" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/10-machine.bats
```

Expected: FAIL — `setup/steps/10-machine.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `setup/steps/10-machine.sh`:

```bash
#!/usr/bin/env bash
# Machine name is the per-machine identifier and shows up in the prompt.
# Overlay configuration is step 35 — it needs gh auth from step 30.

HV_STEP_NAME="machine"
HV_STEP_SCOPE="system"

hv_step_check() {
  [ -n "$(hv::config_get HV_MODULES)" ]
}

hv::_set_machine_name() {
  local name="$1"
  if ! hv::run sudo scutil --set ComputerName "$name" 2>/dev/null; then
    hv::warn "blocked — scutil unavailable; name recorded for config only"
    return 0
  fi
  hv::run sudo scutil --set HostName "$name" 2>/dev/null || true
  hv::run sudo scutil --set LocalHostName "$name" 2>/dev/null || true
  hv::ok "ComputerName / HostName / LocalHostName -> $name"
}

hv::_choose_modules() {
  local existing m enabled selected=""
  existing="$(hv::config_get HV_MODULES)"
  existing="${existing:-core swift web python security apps}"
  for m in $HV_ALL_MODULES; do
    if [ "$m" = "core" ]; then selected="core"; continue; fi
    case " $existing " in *" $m "*) enabled=y ;; *) enabled=n ;; esac
    if hv::confirm "  enable module: $m" "$enabled"; then
      selected="$selected $m"
    fi
  done
  printf '%s\n' "$selected"
}

hv_step_run() {
  hv::step 10 "machine"

  local current suggestion name
  current="$(hv::machine_name)"

  if hv::machine_has_default_name; then
    suggestion="$(hv::suggest_machine_name)"
    hv::log "This Mac is named \"${current:-unset}\"."
    hv::log "Hidden Vector machines get proper names — it is the key for"
    hv::log "per-machine config, and it shows up in your prompt."
    hv::log "Suggestions: $HV_MACHINE_NAMES"
    name="$(hv::ask "Machine name" "$suggestion")"
    hv::_set_machine_name "$name"
  else
    hv::ok "$current"
  fi

  hv::config_set HV_MODULES "$(hv::_choose_modules)"

  if hv::is_managed; then
    hv::config_set HV_RESTRICTED "1"
    hv::ok "restricted mode (MDM-managed)"
  fi

  hv::ok "$(hv::config_file)"
  return 0
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bats tests/steps/10-machine.bats
```

Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
shellcheck -x setup/steps/10-machine.sh
git add setup/steps/10-machine.sh tests/steps/10-machine.bats
git commit -m "feat: add machine naming and module selection step"
```

---

## Task 10: Step 20 — Homebrew, including the shared-prefix case

**Files:**
- Create: `setup/steps/20-homebrew.sh`
- Create: `brew/core.Brewfile`
- Test: `tests/steps/20-homebrew.bats`

**Interfaces:**
- Consumes: `hv::run`, `hv::confirm`, `hv::is_admin`, `hv::warn`
- Produces: `HV_STEP_NAME="homebrew"`, scope `system`; `HV_BREW_PREFIX` (default `/opt/homebrew`)

`/opt/homebrew` is the one shared mutable resource. A second macOS account can run every binary in it but cannot `brew install`. Per the spec, the fix is offered explicitly, never applied silently, and states its tradeoff.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/20-homebrew.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
  export HV_BREW_PREFIX="$BATS_TEST_TMPDIR/homebrew"
  mkdir -p "$HV_BREW_PREFIX/bin"
  hv_stub brew 0 ""
  hv_stub sudo 0 ""
  hv_stub id 0 "staff admin"
  export HV_YES=1
}

@test "check fails when brew is not installed" {
  rm -rf "$HV_BREW_PREFIX"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check passes when brew exists and the core bundle is satisfied" {
  touch "$HV_BREW_PREFIX/bin/brew"; chmod +x "$HV_BREW_PREFIX/bin/brew"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
  hv_assert_called "bundle check"
}

@test "check fails when the core bundle is unsatisfied" {
  touch "$HV_BREW_PREFIX/bin/brew"; chmod +x "$HV_BREW_PREFIX/bin/brew"
  hv_stub brew 1 ""
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "run installs Homebrew when absent" {
  rm -rf "$HV_BREW_PREFIX"
  hv_stub curl 0 "echo installed-homebrew"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  hv_assert_called "curl"
}

@test "run installs the core bundle" {
  touch "$HV_BREW_PREFIX/bin/brew"; chmod +x "$HV_BREW_PREFIX/bin/brew"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  hv_assert_called "bundle --file"
}

@test "run offers the admin-group share when the prefix is not writable" {
  touch "$HV_BREW_PREFIX/bin/brew"; chmod +x "$HV_BREW_PREFIX/bin/brew"
  chmod -w "$HV_BREW_PREFIX"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  [[ "$stderr$output" == *"another account"* ]]
  chmod +w "$HV_BREW_PREFIX"
}

@test "run states the tradeoff before sharing write access" {
  touch "$HV_BREW_PREFIX/bin/brew"; chmod +x "$HV_BREW_PREFIX/bin/brew"
  chmod -w "$HV_BREW_PREFIX"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  [[ "$stderr$output" == *"any admin user"* ]]
  chmod +w "$HV_BREW_PREFIX"
}

@test "run does not chgrp when the prefix is already writable" {
  touch "$HV_BREW_PREFIX/bin/brew"; chmod +x "$HV_BREW_PREFIX/bin/brew"
  source "$HV_ROOT/setup/steps/20-homebrew.sh"
  run hv_step_run
  hv_assert_not_called "chgrp"
}

@test "core Brewfile contains the tools every module depends on" {
  for f in git git-delta gh starship fzf ripgrep bat eza zoxide; do
    grep -q "\"$f\"" "$HV_ROOT/brew/core.Brewfile"
  done
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/20-homebrew.bats
```

Expected: FAIL — neither file exists.

- [ ] **Step 3: Write the core Brewfile**

Create `brew/core.Brewfile`:

```ruby
# Installed on every machine, every module.

# Shell and prompt
brew "starship"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"

# Git
brew "git"
brew "git-delta"
brew "gh"

# CLI tools
brew "bat"
brew "eza"
brew "fzf"
brew "ripgrep"
brew "zoxide"

# Repo tooling
brew "bats-core"
brew "shellcheck"
```

- [ ] **Step 4: Write the minimal implementation**

Create `setup/steps/20-homebrew.sh`:

```bash
#!/usr/bin/env bash
# Homebrew is the one shared mutable resource on a multi-account Mac.

HV_STEP_NAME="homebrew"
HV_STEP_SCOPE="system"

HV_BREW_PREFIX="${HV_BREW_PREFIX:-/opt/homebrew}"

hv::_brew() { "$HV_BREW_PREFIX/bin/brew" "$@"; }

hv::_brew_installed() { [ -x "$HV_BREW_PREFIX/bin/brew" ]; }

hv_step_check() {
  hv::_brew_installed || return 1
  hv::_brew bundle check --file "$HV_ROOT/brew/core.Brewfile" >/dev/null 2>&1
}

hv::_offer_shared_write() {
  hv::warn "$HV_BREW_PREFIX was installed by another account and is not writable by you."
  hv::log "Without write access you can run every Homebrew binary but cannot"
  hv::log "install new ones."
  hv::log ""
  hv::log "Tradeoff: sharing write access means any admin user can place"
  hv::log "executables that another admin later runs. Reasonable between"
  hv::log "trusted users on a shared Mac; not otherwise."
  if hv::confirm "Share write access with the admin group?" n; then
    hv::run sudo chgrp -R admin "$HV_BREW_PREFIX"
    hv::run sudo chmod -R g+w "$HV_BREW_PREFIX"
    hv::ok "admin group can now write $HV_BREW_PREFIX"
    return 0
  fi
  hv::log "Leaving read-only. Missing packages will be reported, not installed."
  return 1
}

hv_step_run() {
  hv::step 20 "homebrew"

  if ! hv::_brew_installed; then
    hv::log "Installing Homebrew…"
    hv::run /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if [ ! -w "$HV_BREW_PREFIX" ]; then
    hv::_offer_shared_write || {
      hv::_brew bundle check --file "$HV_ROOT/brew/core.Brewfile" \
        || hv::warn "core packages missing; ask the account that owns Homebrew to install them"
      return 0
    }
  fi

  hv::run hv::_brew bundle --file "$HV_ROOT/brew/core.Brewfile"
  hv::ok "core packages"
  return 0
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bats tests/steps/20-homebrew.bats
```

Expected: PASS, 9 tests.

- [ ] **Step 6: Commit**

```bash
shellcheck -x setup/steps/20-homebrew.sh
git add setup/steps/20-homebrew.sh brew/core.Brewfile tests/steps/20-homebrew.bats
git commit -m "feat: add Homebrew step with shared-prefix handling"
```

---

## Task 11: Step 30 — identity and commit signing

**Files:**
- Create: `setup/steps/30-identity.sh`
- Create: `git/allowed-signers.hv`
- Test: `tests/steps/30-identity.bats`

**Interfaces:**
- Consumes: `hv::machine_name`, `hv::ask`, `hv::confirm`, `hv::confirm_always`, `hv::run`
- Produces: `HV_STEP_NAME="identity"`, scope `user`. Writes `~/.config/git/identity`, optionally `~/.config/git/identity.hv`, and `~/.config/git/allowed-signers`.

One signing key per account per machine, named after the machine. Private keys never move between machines. `allowed-signers` is regenerated from the tracked team file plus the local user's own public keys, which makes it idempotent by construction.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/30-identity.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/machine.sh"
  source "$HV_ROOT/setup/lib/prompt.sh"
  export HV_GIT_CONFIG_HOME="$HOME/.config/git"
  hv_stub scutil 0 "prometheus"
  hv_stub gh 0 "Mark Adams"
  hv_stub ssh-keygen 0 ""
  export HV_YES=1
}

@test "check fails when no identity file exists" {
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
}

@test "check passes when identity and signing key exist" {
  mkdir -p "$HV_GIT_CONFIG_HOME" "$HOME/.ssh"
  printf '[user]\n\temail = a@b.c\n' > "$HV_GIT_CONFIG_HOME/identity"
  touch "$HOME/.ssh/id_ed25519_signing_prometheus"
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_check
  [ "$status" -eq 0 ]
}

@test "run authenticates gh when not already logged in" {
  hv_stub gh 1 ""
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_run
  hv_assert_called "auth login"
}

@test "run writes a git identity file" {
  source "$HV_ROOT/setup/steps/30-identity.sh"
  hv_step_run
  grep -q "email" "$HV_GIT_CONFIG_HOME/identity"
  grep -q "signingkey" "$HV_GIT_CONFIG_HOME/identity"
}

@test "run names the signing key after the machine" {
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_run
  hv_assert_called "id_ed25519_signing_prometheus"
}

@test "run uploads the signing key to GitHub" {
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_run
  hv_assert_called "ssh-key add"
  hv_assert_called "--type signing"
}

@test "run does not regenerate an existing signing key" {
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/id_ed25519_signing_prometheus"
  source "$HV_ROOT/setup/steps/30-identity.sh"
  run hv_step_run
  hv_assert_not_called "ssh-keygen"
}

@test "run builds allowed-signers from the team file plus own keys" {
  mkdir -p "$HOME/.ssh"
  echo "ssh-ed25519 AAAAOWN own@example.com" > "$HOME/.ssh/id_ed25519_signing_prometheus.pub"
  source "$HV_ROOT/setup/steps/30-identity.sh"
  hv_step_run
  grep -q "AAAAOWN" "$HV_GIT_CONFIG_HOME/allowed-signers"
  grep -q 'namespaces="git"' "$HV_GIT_CONFIG_HOME/allowed-signers"
}

@test "run regenerating allowed-signers does not duplicate entries" {
  mkdir -p "$HOME/.ssh"
  echo "ssh-ed25519 AAAAOWN own@example.com" > "$HOME/.ssh/id_ed25519_signing_prometheus.pub"
  source "$HV_ROOT/setup/steps/30-identity.sh"
  hv_step_run
  hv_step_run
  run grep -c "AAAAOWN" "$HV_GIT_CONFIG_HOME/allowed-signers"
  [ "$output" = "1" ]
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/30-identity.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/30-identity.bats
```

Expected: FAIL — `setup/steps/30-identity.sh` does not exist.

- [ ] **Step 3: Create the team signers file**

Create `git/allowed-signers.hv`:

```
# Public SSH signing keys for Hidden Vector members. Public information.
# Appended to each person's own keys to produce ~/.config/git/allowed-signers.
# Add a line per member per machine:
#   email namespaces="git" ssh-ed25519 AAAA...
```

- [ ] **Step 4: Write the minimal implementation**

Create `setup/steps/30-identity.sh`:

```bash
#!/usr/bin/env bash
# Identity is per-account and travels across a person's machines.
# Signing keys are per-account per-machine and never travel.

HV_STEP_NAME="identity"
HV_STEP_SCOPE="user"

HV_GIT_CONFIG_HOME="${HV_GIT_CONFIG_HOME:-$HOME/.config/git}"

hv::_signing_key() {
  printf '%s\n' "$HOME/.ssh/id_ed25519_signing_$(hv::machine_name)"
}

hv_step_check() {
  [ -f "$HV_GIT_CONFIG_HOME/identity" ] && [ -f "$(hv::_signing_key)" ]
}

hv::_gh_authed() { gh auth status >/dev/null 2>&1; }

hv::_write_identity() {
  local file="$1" name="$2" email="$3" key="$4"
  hv::run mkdir -p "$(dirname "$file")"
  [ "${HV_DRY_RUN:-0}" = "1" ] && return 0
  cat > "$file" <<IDENT
[user]
	name = $name
	email = $email
	signingkey = $key.pub
IDENT
}

hv::_rebuild_allowed_signers() {
  local out="$HV_GIT_CONFIG_HOME/allowed-signers" email="$1" pub
  [ "${HV_DRY_RUN:-0}" = "1" ] && return 0
  hv::run mkdir -p "$HV_GIT_CONFIG_HOME"
  # Regenerated wholesale every run, so it cannot accumulate duplicates.
  cat "$HV_ROOT/git/allowed-signers.hv" > "$out"
  for pub in "$HOME"/.ssh/id_ed25519_signing_*.pub; do
    [ -f "$pub" ] || continue
    printf '%s namespaces="git" %s\n' "$email" "$(cut -d' ' -f1,2 "$pub")" >> "$out"
  done
  hv::ok "$out"
}

hv_step_run() {
  hv::step 30 "identity"

  hv::_gh_authed || hv::run gh auth login

  local name email hv_email key
  name="$(hv::ask "Name" "$(gh api user --jq .name 2>/dev/null || echo "")")"
  email="$(hv::ask "Email" "$(gh api user --jq .email 2>/dev/null || echo "")")"

  key="$(hv::_signing_key)"
  if [ ! -f "$key" ]; then
    hv::log "No signing key for this machine. Generating one."
    hv::log "(One key per machine — private keys never move between Macs.)"
    hv::run mkdir -p "$HOME/.ssh"
    hv::run ssh-keygen -t ed25519 -N "" -C "$(hv::machine_name) signing" -f "$key"
    hv::run gh ssh-key add "$key.pub" --type signing \
      --title "$(hv::machine_name) (signing)"
    hv::ok "$key"
  else
    hv::ok "signing key present"
  fi

  hv::_write_identity "$HV_GIT_CONFIG_HOME/identity" "$name" "$email" "$key"

  if hv::confirm "Different email for Hidden Vector client repos?" n; then
    hv_email="$(hv::ask "HV email" "$email")"
    hv::_write_identity "$HV_GIT_CONFIG_HOME/identity.hv" "$name" "$hv_email" "$key"
    hv::ok "includeIf gitdir:~/Developer/github.com/hiddenvector/"
  fi

  hv::_rebuild_allowed_signers "$email"
  return 0
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bats tests/steps/30-identity.bats
```

Expected: PASS, 10 tests.

- [ ] **Step 6: Commit**

```bash
shellcheck -x setup/steps/30-identity.sh
git add setup/steps/30-identity.sh git/allowed-signers.hv tests/steps/30-identity.bats
git commit -m "feat: add identity and per-machine commit signing step"
```

---

## Task 12: Step 35 — overlay detection and creation

**Files:**
- Create: `setup/steps/35-overlay.sh`
- Test: `tests/steps/35-overlay.bats`

**Interfaces:**
- Consumes: `hv::config_get`, `hv::config_set`, `hv::confirm`, `hv::confirm_always`, `hv::ask`, `hv::run`
- Produces: `HV_STEP_NAME="overlay"`, scope `user`. Sets `HV_OVERLAY` in `~/.config/hv/config`.

Three cases per the spec: already configured, exists on GitHub but unconfigured, or does not exist. Asking a newcomer for an overlay URL they do not have is a dead end, so the third case offers to create it. `gh repo create` publishes to the internet, so it goes through `hv::confirm_always` — `--yes` must not be able to trigger it — and defaults to private.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/35-overlay.bats`:

```bash
#!/usr/bin/env bats

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

@test "run offers an existing GitHub repo as the default" {
  source "$HV_ROOT/setup/steps/35-overlay.sh"
  run hv_step_run
  [[ "$output" == *"someuser/dotfiles"* ]]
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
  run bash -c "yes y | { source '$HV_ROOT/setup/lib/log.sh'; source '$HV_ROOT/setup/lib/config.sh'; source '$HV_ROOT/setup/lib/prompt.sh'; source '$HV_ROOT/setup/steps/35-overlay.sh'; hv_step_run; }"
  hv_assert_called "--private"
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/35-overlay.bats
```

Expected: FAIL — `setup/steps/35-overlay.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `setup/steps/35-overlay.sh`:

```bash
#!/usr/bin/env bash
# An overlay is a person's own layer on top of the shared base. Without one,
# personal config lands in untracked files that neither survive a machine wipe
# nor sync between a person's own Macs.
#
# Must run after step 30 (needs gh auth) and before step 40 (the overlay's
# git/config is included when the gitconfig is linked).

HV_STEP_NAME="overlay"
HV_STEP_SCOPE="user"

hv_step_check() {
  local configured
  configured="$(hv::config_get HV_OVERLAY)"
  [ -z "$configured" ] && return 1
  [ "$configured" = "none" ] && return 0
  [ -d "$configured" ]
}

hv::_scaffold_overlay() {
  local dir="$1"
  hv::run mkdir -p "$dir/brew" "$dir/zshrc.d" "$dir/git"
  [ "${HV_DRY_RUN:-0}" = "1" ] && return 0

  [ -f "$dir/brew/personal.Brewfile" ] || cat > "$dir/brew/personal.Brewfile" <<'EOF'
# Your own packages. Installed after the Hidden Vector modules.
# cask "chatgpt"
EOF

  [ -f "$dir/zshrc.d/personal.zsh" ] || cat > "$dir/zshrc.d/personal.zsh" <<'EOF'
# Your own shell config. Sourced after the Hidden Vector defaults, so it wins.
# alias gs='git status'
EOF

  [ -f "$dir/git/config" ] || cat > "$dir/git/config" <<'EOF'
# Your own git settings. Included after the base gitconfig, so these win.
EOF

  [ -f "$dir/README.md" ] || cat > "$dir/README.md" <<'EOF'
# Personal overlay

Your layer on top of [hiddenvector/dotfiles](https://github.com/hiddenvector/dotfiles).
Everything here follows you to every Mac you set up.

| Path | What goes in it |
|---|---|
| `brew/*.Brewfile` | packages you want that the shared modules do not install |
| `zshrc.d/*.zsh` | your aliases and shell config — sourced after the defaults, so they win |
| `git/config` | your git settings — included after the base config, so they win |
| `macos.sh` | extra `defaults write` commands, run after the shared ones |
| `steps/*.sh` | extra setup steps, if you ever need them |

## Using it

Edit a file, commit, push. On your other Mac:

```bash
git -C ~/Developer/github.com/<you>/dotfiles pull
hv setup
```

That is the whole workflow.
EOF
  hv::ok "scaffolded $dir"
}

# Move untracked personal config into the overlay, where it gets versioned.
hv::_migrate_local() {
  local dir="$1" src
  src="${HV_CONFIG_HOME:-$HOME/.config/hv}/local.Brewfile"
  if [ -s "$src" ]; then
    cat "$src" >> "$dir/brew/personal.Brewfile"
    hv::run rm -f "$src"
    hv::ok "moved local.Brewfile into the overlay"
  fi
  src="$HOME/.zshrc.d/local.zsh"
  if [ -s "$src" ] && ! grep -q '^# Machine-specific' "$src"; then
    cat "$src" >> "$dir/zshrc.d/personal.zsh"
    hv::ok "moved local.zsh into the overlay"
  fi
}

hv_step_run() {
  hv::step 35 "overlay"

  local configured handle default_repo dir url visibility
  configured="$(hv::config_get HV_OVERLAY)"

  # Case 1: already configured — clone it if the directory is missing.
  if [ -n "$configured" ] && [ "$configured" != "none" ]; then
    if [ ! -d "$configured" ]; then
      url="$(hv::config_get HV_OVERLAY_URL)"
      hv::run git clone "$url" "$configured"
    fi
    hv::ok "$configured"
    return 0
  fi

  hv::log "An overlay is your personal layer on top of the Hidden Vector base —"
  hv::log "your own packages, aliases and git settings, tracked in your own repo"
  hv::log "so they follow you to every Mac you use."

  handle="$(gh api user --jq .login 2>/dev/null || echo "")"
  default_repo="$handle/dotfiles"
  dir="${HV_OVERLAY_DIR:-$HOME/Developer/github.com/$handle/dotfiles}"

  # Case 2: it already exists on GitHub — offer it as the default.
  if gh repo view "$default_repo" >/dev/null 2>&1; then
    hv::log "Found $default_repo."
    if hv::confirm "Use it as your overlay?" y; then
      hv::run git clone "https://github.com/$default_repo" "$dir"
      hv::config_set HV_OVERLAY "$dir"
      hv::config_set HV_OVERLAY_URL "https://github.com/$default_repo"
      hv::ok "$dir"
      return 0
    fi
  fi

  # Case 3: create it. Outward-facing, so --yes must not trigger this.
  if ! hv::confirm_always "You don't have one yet. Create it?"; then
    hv::config_set HV_OVERLAY "none"
    hv::log "Skipped. Run 'hv overlay init' whenever you want one."
    return 0
  fi

  default_repo="$(hv::ask "Repo name" "$default_repo")"
  visibility="$(hv::ask "Visibility" "private")"

  hv::run gh repo create "$default_repo" "--$visibility" \
    --description "Personal Hidden Vector dotfiles overlay"
  hv::run git clone "https://github.com/$default_repo" "$dir"
  hv::_scaffold_overlay "$dir"
  hv::_migrate_local "$dir"
  hv::run git -C "$dir" add -A
  hv::run git -C "$dir" commit -m "Scaffold personal overlay"
  hv::run git -C "$dir" push -u origin HEAD

  hv::config_set HV_OVERLAY "$dir"
  hv::config_set HV_OVERLAY_URL "https://github.com/$default_repo"
  hv::ok "created github.com/$default_repo"
  return 0
}
```

- [ ] **Step 4: Teach the runner about overlay steps**

The spec's overlay contract includes `steps/*.sh` — "optional extra converge
steps" — which nothing yet runs. In `bin/hv`, replace `hv::steps`:

```bash
hv::steps() {
  local overlay
  ls "$HV_STEPS_DIR"/*.sh 2>/dev/null | sort
  overlay="$(hv::config_get HV_OVERLAY 2>/dev/null || true)"
  if [ -n "$overlay" ] && [ "$overlay" != "none" ] && [ -d "$overlay/steps" ]; then
    ls "$overlay"/steps/*.sh 2>/dev/null | sort
  fi
}
```

Overlay steps run after the base steps, matching the "overlay applied last"
rule the rest of the contract follows.

- [ ] **Step 5: Test it**

Append to `tests/bin/hv.bats`:

```bash
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
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
bats tests/steps/35-overlay.bats tests/bin/hv.bats
```

Expected: PASS, 12 + 13 tests.

- [ ] **Step 7: Commit**

```bash
shellcheck -x setup/steps/35-overlay.sh bin/hv
git add setup/steps/35-overlay.sh bin/hv tests/steps/35-overlay.bats tests/bin/hv.bats
git commit -m "feat: detect, adopt or create a personal overlay repo"
```

---

## Task 13: Step 40 — symlinks and the identity-free gitconfig

**Files:**
- Create: `setup/steps/40-symlinks.sh`
- Create: `git/gitconfig`, `git/gitignore_global`
- Create: `zsh/.zprofile`, `zsh/.zshrc`, `zsh/.zshrc.d/{eza,fzf,git,zoxide}.zsh`
- Create: `config/starship.toml`
- Test: `tests/steps/40-symlinks.bats`

**Interfaces:**
- Consumes: `hv::link`, `hv::linked`, `hv::config_get`
- Produces: `HV_STEP_NAME="symlinks"`, scope `user`

The tracked gitconfig contains **zero identity**. It ends with three includes, in precedence order: the user's identity, a conditional HV identity for client repos, and `~/.config/git/local`, which step 40 generates to point at the overlay's `git/config`. The tracked file cannot know the overlay path, so the generated file is the indirection.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/40-symlinks.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/link.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  export HV_GIT_CONFIG_HOME="$HOME/.config/git"
}

@test "tracked gitconfig contains no identity" {
  ! grep -qE '^\s*(name|email|signingkey)\s*=' "$HV_ROOT/git/gitconfig"
}

@test "tracked gitconfig includes the identity file" {
  grep -q 'path = ~/.config/git/identity' "$HV_ROOT/git/gitconfig"
}

@test "tracked gitconfig conditionally includes the HV identity" {
  grep -q 'includeIf "gitdir:~/Developer/github.com/hiddenvector/"' "$HV_ROOT/git/gitconfig"
}

@test "tracked gitconfig includes the generated local file last" {
  local last
  last="$(grep -n 'path = ~/.config/git/' "$HV_ROOT/git/gitconfig" | tail -1)"
  [[ "$last" == *"local"* ]]
}

@test "run links the core dotfiles" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  [ -L "$HOME/.gitconfig" ]
  [ -L "$HOME/.gitignore_global" ]
  [ -L "$HOME/.zshrc" ]
  [ -L "$HOME/.zprofile" ]
  [ -L "$HOME/.config/starship.toml" ]
}

@test "run links every zshrc.d fragment" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  [ -L "$HOME/.zshrc.d/git.zsh" ]
  [ -L "$HOME/.zshrc.d/fzf.zsh" ]
}

@test "run links bin executables onto PATH" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  [ -L "$HOME/.local/bin/hv" ]
}

@test "run creates the secrets stub with 0600 permissions" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  [ -f "$HOME/.secrets" ]
  [ "$(stat -f '%Lp' "$HOME/.secrets")" = "600" ]
}

@test "run points the generated git local file at the overlay" {
  mkdir -p "$HOME/overlay/git"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  hv::config_load
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  grep -q "$HOME/overlay/git/config" "$HV_GIT_CONFIG_HOME/local"
}

@test "run writes an empty git local file when there is no overlay" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  [ -f "$HV_GIT_CONFIG_HOME/local" ]
  ! grep -q "overlay" "$HV_GIT_CONFIG_HOME/local"
}

@test "run is idempotent" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  hv_step_run
  run hv_step_run
  [ "$status" -eq 0 ]
  [ -L "$HOME/.zshrc" ]
}

@test "check fails before running and passes after" {
  source "$HV_ROOT/setup/steps/40-symlinks.sh"
  run hv_step_check
  [ "$status" -eq 1 ]
  hv_step_run
  run hv_step_check
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/40-symlinks.bats
```

Expected: FAIL — none of the payload files exist.

- [ ] **Step 3: Write the identity-free gitconfig**

Create `git/gitconfig`. This is the existing `.gitconfig` with the `[user]` block removed and three includes appended:

```
[init]
	defaultBranch = main
[pull]
	rebase = true
[rebase]
	autoStash = true
[fetch]
	prune = true
[rerere]
	enabled = true
[help]
	autocorrect = prompt
[core]
	editor = code --wait
	pager = delta
	excludesfile = ~/.gitignore_global
[interactive]
	diffFilter = delta --color-only
[delta]
	navigate = true
	side-by-side = true
[diff]
	algorithm = histogram
[merge]
	conflictstyle = zdiff3
[push]
	autoSetupRemote = true
[branch]
	sort = -committerdate
[credential]
	helper =
[credential "https://github.com"]
	helper =
	helper = !/opt/homebrew/bin/gh auth git-credential
[credential "https://gist.github.com"]
	helper =
	helper = !/opt/homebrew/bin/gh auth git-credential
[gpg]
	format = ssh
[commit]
	gpgsign = true
[tag]
	gpgsign = true
[gpg "ssh"]
	allowedSignersFile = ~/.config/git/allowed-signers
[filter "lfs"]
	clean = git-lfs clean -- %f
	smudge = git-lfs smudge -- %f
	process = git-lfs filter-process
	required = true

# Identity lives outside this repo. Later includes win.
[include]
	path = ~/.config/git/identity
[includeIf "gitdir:~/Developer/github.com/hiddenvector/"]
	path = ~/.config/git/identity.hv
[include]
	path = ~/.config/git/local
```

- [ ] **Step 4: Copy the remaining payload files unchanged**

These carry over from `hyperspacemark/dotfiles` with no edits:

```bash
OLD=~/Developer/github.com/hyperspacemark/dotfiles
cp "$OLD/.gitignore_global" git/gitignore_global
cp "$OLD/config/starship.toml" config/starship.toml
cp "$OLD/zsh/.zprofile" "$OLD/zsh/.zshrc" zsh/
mkdir -p zsh/.zshrc.d
cp "$OLD/zsh/.zshrc.d/eza.zsh" "$OLD/zsh/.zshrc.d/fzf.zsh" \
   "$OLD/zsh/.zshrc.d/git.zsh" "$OLD/zsh/.zshrc.d/zoxide.zsh" zsh/.zshrc.d/
```

Then edit `zsh/.zshrc` to source the overlay after the base fragments. Append:

```bash
# Overlay fragments, sourced last so they win.
if [ -n "${HV_OVERLAY:-}" ] && [ -d "$HV_OVERLAY/zshrc.d" ]; then
  for f in "$HV_OVERLAY"/zshrc.d/*.zsh; do
    [ -r "$f" ] && source "$f"
  done
fi
```

- [ ] **Step 5: Write the minimal implementation**

Create `setup/steps/40-symlinks.sh`:

```bash
#!/usr/bin/env bash
# Links tracked config into place and generates the git indirection file
# that points at the overlay.

HV_STEP_NAME="symlinks"
HV_STEP_SCOPE="user"

HV_GIT_CONFIG_HOME="${HV_GIT_CONFIG_HOME:-$HOME/.config/git}"

hv::_pairs() {
  printf '%s\t%s\n' \
    "$HV_ROOT/git/gitconfig"         "$HOME/.gitconfig" \
    "$HV_ROOT/git/gitignore_global"  "$HOME/.gitignore_global" \
    "$HV_ROOT/config/starship.toml"  "$HOME/.config/starship.toml" \
    "$HV_ROOT/zsh/.zprofile"         "$HOME/.zprofile" \
    "$HV_ROOT/zsh/.zshrc"            "$HOME/.zshrc"
}

hv_step_check() {
  local src dst
  while IFS=$'\t' read -r src dst; do
    hv::linked "$src" "$dst" || return 1
  done <<EOF
$(hv::_pairs)
EOF
  hv::linked "$HV_ROOT/bin/hv" "$HOME/.local/bin/hv" || return 1
  [ -f "$HV_GIT_CONFIG_HOME/local" ]
}

hv::_write_git_local() {
  local overlay
  overlay="$(hv::config_get HV_OVERLAY)"
  hv::run mkdir -p "$HV_GIT_CONFIG_HOME"
  [ "${HV_DRY_RUN:-0}" = "1" ] && return 0
  {
    printf '# Generated by hv setup. Do not edit; edit your overlay instead.\n'
    if [ -n "$overlay" ] && [ "$overlay" != "none" ] && [ -f "$overlay/git/config" ]; then
      printf '[include]\n\tpath = %s/git/config\n' "$overlay"
    fi
  } > "$HV_GIT_CONFIG_HOME/local"
}

hv_step_run() {
  hv::step 40 "symlinks"

  local src dst f
  while IFS=$'\t' read -r src dst; do
    hv::link "$src" "$dst"
  done <<EOF
$(hv::_pairs)
EOF

  hv::run mkdir -p "$HOME/.local/bin" "$HOME/.zshrc.d" "$HOME/.zsh/cache"

  for f in "$HV_ROOT"/zsh/.zshrc.d/*.zsh; do
    hv::link "$f" "$HOME/.zshrc.d/$(basename "$f")"
  done

  for f in "$HV_ROOT"/bin/*; do
    [ -x "$f" ] || continue
    hv::link "$f" "$HOME/.local/bin/$(basename "$f")"
  done

  hv::_write_git_local

  if [ ! -f "$HOME/.secrets" ] && [ "${HV_DRY_RUN:-0}" != "1" ]; then
    cat > "$HOME/.secrets" <<'EOF'
# Secrets — never commit this file.
# export GITHUB_TOKEN=""
# export ANTHROPIC_API_KEY=""
EOF
    chmod 600 "$HOME/.secrets"
    hv::ok "created ~/.secrets"
  fi

  if [ ! -f "$HOME/.zshrc.d/local.zsh" ] && [ "${HV_DRY_RUN:-0}" != "1" ]; then
    cat > "$HOME/.zshrc.d/local.zsh" <<'EOF'
# Machine-specific config, not tracked anywhere.
# Anything you want on every Mac belongs in your overlay instead.
[[ -f ~/.secrets ]] && source ~/.secrets
EOF
    hv::ok "created ~/.zshrc.d/local.zsh"
  fi

  return 0
}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
bats tests/steps/40-symlinks.bats
```

Expected: PASS, 12 tests.

- [ ] **Step 7: Commit**

```bash
shellcheck -x setup/steps/40-symlinks.sh
git add setup/steps/40-symlinks.sh git/ zsh/ config/ tests/steps/40-symlinks.bats
git commit -m "feat: add symlink step and identity-free gitconfig"
```

---

## Task 14: Step 50 — module packages, overlay packages, restricted mode

**Files:**
- Create: `setup/steps/50-packages.sh`
- Create: `brew/{swift,web,python,security,apps}.Brewfile`
- Create: `config/vscode-extensions.txt`
- Test: `tests/steps/50-packages.bats`

**Interfaces:**
- Consumes: `hv::modules`, `hv::config_get`, `hv::run`, `hv::warn`
- Produces: `HV_STEP_NAME="packages"`, scope `user`

`HV_RESTRICTED=1` means exactly one thing: do not shell out to `code --install-extension`, because corporate SSL inspection breaks it. Print the list for manual installation instead. Everything else corp-specific belongs in the overlay.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/50-packages.bats`:

```bash
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
  hv::config_set HV_MODULES "core web"
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/50-packages.bats
```

Expected: FAIL — module Brewfiles do not exist.

- [ ] **Step 3: Write the module Brewfiles**

`brew/swift.Brewfile`:

```ruby
# Swift and Xcode tooling. Serves: recipes
brew "xcbeautify"
brew "swiftlint"
```

`brew/web.Brewfile`:

```ruby
# Serves: the-house, mkw-data-api, hiddenvector.studio
# Node itself is owned by fnm, never by Homebrew.
brew "fnm"
brew "supabase/tap/supabase"
brew "railway"
brew "jq"
```

`brew/python.Brewfile`:

```ruby
# Serves: the-house backend (FastAPI)
brew "pyenv"
brew "uv"
```

`brew/security.Brewfile`:

```ruby
# Serves: the-house (.pre-commit-config.yaml runs gitleaks)
brew "gitleaks"
brew "pre-commit"
```

`brew/apps.Brewfile`:

```ruby
cask "visual-studio-code"
cask "github"
cask "db-browser-for-sqlite"
```

`config/vscode-extensions.txt`:

```
eamodio.gitlens
editorconfig.editorconfig
llvm-vs-code-extensions.lldb-dap
swiftlang.swift-vscode
tamasfe.even-better-toml
usernamehw.errorlens
vscodevim.vim
```

- [ ] **Step 4: Write the minimal implementation**

Create `setup/steps/50-packages.sh`:

```bash
#!/usr/bin/env bash
# Module bundles, then the overlay's. HV_RESTRICTED means exactly one thing:
# do not shell out to `code --install-extension`, which corporate SSL
# inspection breaks.

HV_STEP_NAME="packages"
HV_STEP_SCOPE="user"

HV_BREW_PREFIX="${HV_BREW_PREFIX:-/opt/homebrew}"

hv::_bundle() {
  local file="$1"
  [ -f "$file" ] || return 0
  hv::run "$HV_BREW_PREFIX/bin/brew" bundle --file "$file"
}

hv_step_check() {
  local m
  for m in $(hv::modules); do
    "$HV_BREW_PREFIX/bin/brew" bundle check \
      --file "$HV_ROOT/brew/$m.Brewfile" >/dev/null 2>&1 || return 1
  done
  return 0
}

hv::_vscode_extensions() {
  local ext
  if [ "$(hv::config_get HV_RESTRICTED)" = "1" ]; then
    hv::warn "restricted mode — install these extensions by hand:"
    while read -r ext; do
      [ -n "$ext" ] && hv::log "    $ext"
    done < "$HV_ROOT/config/vscode-extensions.txt"
    return 0
  fi
  while read -r ext; do
    [ -n "$ext" ] && hv::run code --install-extension "$ext" --force
  done < "$HV_ROOT/config/vscode-extensions.txt"
  hv::ok "VS Code extensions"
}

hv_step_run() {
  hv::step 50 "packages"

  local m overlay f
  for m in $(hv::modules); do
    hv::_bundle "$HV_ROOT/brew/$m.Brewfile"
    hv::ok "$m"
  done

  overlay="$(hv::config_get HV_OVERLAY)"
  if [ -n "$overlay" ] && [ "$overlay" != "none" ] && [ -d "$overlay/brew" ]; then
    for f in "$overlay"/brew/*.Brewfile; do
      [ -f "$f" ] && hv::_bundle "$f"
    done
    hv::ok "overlay packages"
  fi

  hv::module_enabled apps && hv::_vscode_extensions
  return 0
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bats tests/steps/50-packages.bats
```

Expected: PASS, 9 tests.

- [ ] **Step 6: Commit**

```bash
shellcheck -x setup/steps/50-packages.sh
git add setup/steps/50-packages.sh brew/ config/vscode-extensions.txt tests/steps/50-packages.bats
git commit -m "feat: add module and overlay package installation"
```

---

## Task 15: Step 60 — macOS defaults

**Files:**
- Create: `setup/steps/60-macos.sh`
- Test: `tests/steps/60-macos.bats`

**Interfaces:**
- Consumes: `hv::run`, `hv::config_get`
- Produces: `HV_STEP_NAME="macos"`, scope `user`

This is `macos.sh` from the old repo **with the Touch ID block removed** — that moved to step 05, where it runs before anything else needs `sudo`. Every remaining setting is per-account (`defaults write` targets `~/Library/Preferences`), which is what lets two accounts on one Mac differ.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/60-macos.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  hv_stub defaults 0 ""
  hv_stub killall 0 ""
}

@test "run writes trackpad, keyboard, dock and finder defaults" {
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_called "TrackpadThreeFingerDrag"
  hv_assert_called "KeyRepeat"
  hv_assert_called "com.apple.dock autohide"
  hv_assert_called "ShowPathbar"
}

@test "run does not touch Touch ID — that is step 05" {
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_not_called "pam_tid"
  hv_assert_not_called "sudo_local"
}

@test "run applies the overlay's macos.sh when present" {
  mkdir -p "$HOME/overlay"
  echo 'echo overlay-macos-ran' > "$HOME/overlay/macos.sh"
  chmod +x "$HOME/overlay/macos.sh"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  [[ "$output" == *"overlay-macos-ran"* ]]
}

@test "run warns that three-finger drag needs a logout" {
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  [[ "$stderr$output" == *"logout"* ]]
}

@test "run under dry run writes nothing" {
  HV_DRY_RUN=1
  source "$HV_ROOT/setup/steps/60-macos.sh"
  run hv_step_run
  hv_assert_not_called "TrackpadThreeFingerDrag"
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/60-macos.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/60-macos.bats
```

Expected: FAIL — `setup/steps/60-macos.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `setup/steps/60-macos.sh`:

```bash
#!/usr/bin/env bash
# Every setting here is per-account: `defaults write` targets
# ~/Library/Preferences. Touch ID is step 05, not here.

HV_STEP_NAME="macos"
HV_STEP_SCOPE="user"

# defaults are cheap to reapply and awkward to verify; always converge.
hv_step_check() { return 1; }

hv_step_run() {
  hv::step 60 "macOS defaults"

  # Trackpad — three-finger drag lives in Accessibility, needs both domains.
  hv::run defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -int 1
  hv::run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -int 1
  hv::run defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  hv::run defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
  hv::run defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerDoubleTapGesture -int 1
  hv::run defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 0

  # Keyboard
  hv::run defaults write NSGlobalDomain KeyRepeat -int 2
  hv::run defaults write NSGlobalDomain InitialKeyRepeat -int 15
  hv::run defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  hv::run defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  hv::run defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

  # Dock
  hv::run defaults write com.apple.dock autohide -bool true
  hv::run defaults write com.apple.dock tilesize -int 64

  # Finder
  hv::run defaults write com.apple.finder ShowPathbar -bool true
  hv::run defaults write com.apple.finder FXPreferredViewStyle -string "clmv"
  hv::run defaults write com.apple.finder AppleShowAllFiles -bool true

  hv::run killall Dock 2>/dev/null || true
  hv::run killall Finder 2>/dev/null || true
  hv::ok "trackpad, keyboard, dock, finder"

  local overlay
  overlay="$(hv::config_get HV_OVERLAY)"
  if [ -n "$overlay" ] && [ -x "$overlay/macos.sh" ]; then
    hv::run "$overlay/macos.sh"
    hv::ok "overlay macos.sh"
  fi

  hv::warn "three-finger drag needs a logout to take effect"
  return 0
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bats tests/steps/60-macos.bats
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
shellcheck -x setup/steps/60-macos.sh
git add setup/steps/60-macos.sh tests/steps/60-macos.bats
git commit -m "feat: add macOS defaults step without the Touch ID block"
```

---

## Task 16: Step 70 — language toolchains

**Files:**
- Create: `setup/steps/70-toolchains.sh`
- Test: `tests/steps/70-toolchains.bats`

**Interfaces:**
- Consumes: `hv::module_enabled`, `hv::run`
- Produces: `HV_STEP_NAME="toolchains"`, scope `user`

Node is owned entirely by `fnm`, never by Homebrew — the old repo learned this the hard way (`Remove node/pnpm from Brewfile, let fnm own Node`). `.nvmrc` in `the-house` pins Node 22, which `fnm` reads.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/70-toolchains.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  hv_stub fnm 0 ""
  hv_stub npm 0 ""
  hv_stub pyenv 0 ""
  hv::config_set HV_MODULES "core web python"
  hv::config_load
}

@test "run installs Node LTS and sets it as the default" {
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  hv_assert_called "install --lts"
  hv_assert_called "default lts-latest"
}

@test "run installs the npm globals" {
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  hv_assert_called "pnpm"
  hv_assert_called "vercel"
}

@test "run skips Node entirely without the web module" {
  hv::config_set HV_MODULES "core python"
  hv::config_load
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  hv_assert_not_called "install --lts"
}

@test "run skips Python without the python module" {
  hv::config_set HV_MODULES "core web"
  hv::config_load
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  hv_assert_not_called "pyenv"
}

@test "run does not install Node through Homebrew" {
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  run hv_step_run
  hv_assert_not_called "brew install node"
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/70-toolchains.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/70-toolchains.bats
```

Expected: FAIL — `setup/steps/70-toolchains.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `setup/steps/70-toolchains.sh`:

```bash
#!/usr/bin/env bash
# Node belongs to fnm, never to Homebrew. Python belongs to pyenv.

HV_STEP_NAME="toolchains"
HV_STEP_SCOPE="user"

hv_step_check() {
  if hv::module_enabled web; then
    command -v fnm >/dev/null 2>&1 || return 1
    fnm current >/dev/null 2>&1 || return 1
  fi
  if hv::module_enabled python; then
    command -v pyenv >/dev/null 2>&1 || return 1
  fi
  return 0
}

hv_step_run() {
  hv::step 70 "toolchains"

  if hv::module_enabled web; then
    hv::run fnm install --lts
    hv::run fnm default lts-latest
    hv::run npm install -g pnpm vercel
    hv::ok "Node (fnm) + pnpm, vercel"
  fi

  if hv::module_enabled python; then
    hv::run pyenv install --skip-existing 3.13
    hv::run pyenv global 3.13
    hv::ok "Python (pyenv)"
  fi

  return 0
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bats tests/steps/70-toolchains.bats
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
shellcheck -x setup/steps/70-toolchains.sh
git add setup/steps/70-toolchains.sh tests/steps/70-toolchains.bats
git commit -m "feat: add language toolchain step"
```

---

## Task 17: Step 80 — agent rails

**Files:**
- Create: `setup/steps/80-agents.sh`
- Create: `claude/CLAUDE.md`, `claude/settings.json`
- Test: `tests/steps/80-agents.bats`

**Interfaces:**
- Consumes: `hv::link`, `hv::run`
- Produces: `HV_STEP_NAME="agents"`, scope `user`

House rules must be **composable**: a person may already have a `~/.claude/CLAUDE.md`. The repo's rules are linked to `~/.claude/hv/house-rules.md` and referenced by a single `@import` line, prepended to the existing file if it lacks one. Nothing pre-existing is overwritten.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/80-agents.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/link.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  hv_stub claude 0 ""
}

@test "run links the house rules" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  [ -L "$HOME/.claude/hv/house-rules.md" ]
}

@test "run creates CLAUDE.md with the import when none exists" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  grep -q "@~/.claude/hv/house-rules.md" "$HOME/.claude/CLAUDE.md"
}

@test "run preserves an existing CLAUDE.md" {
  mkdir -p "$HOME/.claude"
  echo "# My own notes" > "$HOME/.claude/CLAUDE.md"
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  grep -q "My own notes" "$HOME/.claude/CLAUDE.md"
  grep -q "@~/.claude/hv/house-rules.md" "$HOME/.claude/CLAUDE.md"
}

@test "run does not add the import twice" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  hv_step_run
  run grep -c "house-rules.md" "$HOME/.claude/CLAUDE.md"
  [ "$output" = "1" ]
}

@test "run links the toolbelt skill" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  hv_step_run
  [ -L "$HOME/.claude/skills/hv-toolbelt" ]
}

@test "run installs the superpowers plugin" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  run hv_step_run
  hv_assert_called "superpowers"
}

@test "house rules do not inline the tool reference" {
  # The reference belongs in the lazily-loaded skill, not in every session.
  run wc -l < "$HV_ROOT/claude/CLAUDE.md"
  [ "$output" -lt 60 ]
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/80-agents.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/80-agents.bats
```

Expected: FAIL — `setup/steps/80-agents.sh` does not exist.

- [ ] **Step 3: Write the house rules**

Create `claude/CLAUDE.md`. Keep it under 60 lines — it loads on **every** session, so the tool reference goes in the lazily-loaded skill instead:

```markdown
# Hidden Vector house rules

## How we work

- **Issues drive work.** Meaningful changes are represented by a GitHub issue.
- **Small, shippable units.** Decompose so each piece lands in one pull request.
- **Explicit tradeoffs.** Scope is intentional. Say what you are not doing.
- **Human control over automation.** Especially for AI-driven functionality:
  preview and diff before applying, never destructive by default.

## Before writing code

- Understand the problem before proposing a fix. If you are debugging, find the
  root cause; do not pattern-match a plausible patch.
- Design before implementing. Say what you intend, get agreement, then build.
- Write the failing test first. Watch it fail for the expected reason.

## Before claiming done

- Run the tests. Paste the output. "Should work" is not evidence.
- If something is broken, say so plainly with the failing output.
- If you skipped part of the task, say which part and why.

## Style

- Match the surrounding code: its naming, its comment density, its idioms.
- Prefer explicit over clever. Prefer small and testable over general.
- Do not add abstraction until there are two real callers.

## Tooling

This machine is set up by [hiddenvector/dotfiles](https://github.com/hiddenvector/dotfiles).
For the shell helpers available here — and which of them will hang a
non-interactive agent — use the `hv-toolbelt` skill.
```

- [ ] **Step 4: Write the shared settings**

Create `claude/settings.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "includeCoAuthoredBy": true,
  "permissions": {
    "allow": [
      "Bash(hv check)",
      "Bash(hv cheatsheet:*)",
      "Bash(git status)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(rg:*)",
      "Bash(bats:*)",
      "Bash(shellcheck:*)"
    ]
  }
}
```

- [ ] **Step 5: Write the minimal implementation**

Create `setup/steps/80-agents.sh`:

```bash
#!/usr/bin/env bash
# House rules compose with whatever the person already has: the repo's rules
# are linked and referenced by one @import line, never written over theirs.

HV_STEP_NAME="agents"
HV_STEP_SCOPE="user"

HV_CLAUDE_HOME="${HV_CLAUDE_HOME:-$HOME/.claude}"
HV_IMPORT_LINE="@~/.claude/hv/house-rules.md"

hv_step_check() {
  hv::linked "$HV_ROOT/claude/CLAUDE.md" "$HV_CLAUDE_HOME/hv/house-rules.md" \
    && grep -q "house-rules.md" "$HV_CLAUDE_HOME/CLAUDE.md" 2>/dev/null
}

hv_step_run() {
  hv::step 80 "agents"

  hv::link "$HV_ROOT/claude/CLAUDE.md" "$HV_CLAUDE_HOME/hv/house-rules.md"
  hv::link "$HV_ROOT/claude/settings.json" "$HV_CLAUDE_HOME/settings.json"
  hv::link "$HV_ROOT/claude/skills/hv-toolbelt" "$HV_CLAUDE_HOME/skills/hv-toolbelt"

  if [ "${HV_DRY_RUN:-0}" != "1" ]; then
    if [ ! -f "$HV_CLAUDE_HOME/CLAUDE.md" ]; then
      printf '%s\n' "$HV_IMPORT_LINE" > "$HV_CLAUDE_HOME/CLAUDE.md"
      hv::ok "created ~/.claude/CLAUDE.md"
    elif ! grep -q "house-rules.md" "$HV_CLAUDE_HOME/CLAUDE.md"; then
      printf '%s\n\n%s' "$HV_IMPORT_LINE" "$(cat "$HV_CLAUDE_HOME/CLAUDE.md")" \
        > "$HV_CLAUDE_HOME/CLAUDE.md.tmp"
      mv "$HV_CLAUDE_HOME/CLAUDE.md.tmp" "$HV_CLAUDE_HOME/CLAUDE.md"
      hv::ok "added house rules import to your existing CLAUDE.md"
    else
      hv::ok "house rules already imported"
    fi
  fi

  hv::run claude plugin install superpowers@claude-plugins-official || \
    hv::warn "could not install the superpowers plugin; install it manually"

  return 0
}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
bats tests/steps/80-agents.bats
```

Expected: PASS, 8 tests.

- [ ] **Step 7: Commit**

```bash
shellcheck -x setup/steps/80-agents.sh
git add setup/steps/80-agents.sh claude/CLAUDE.md claude/settings.json tests/steps/80-agents.bats
git commit -m "feat: add composable agent rails"
```

---

## Task 18: Non-interactive helpers move to `bin/`

**Files:**
- Create: `bin/gprune`, `bin/gbd`
- Modify: `zsh/.zshrc.d/git.zsh` — remove the `gprune` and `gbd` function bodies, keep the completions
- Test: `tests/bin/helpers.bats`

**Interfaces:**
- Produces: `gprune` and `gbd` as executables on `PATH`, callable by agents, scripts, Makefiles and CI.

Shell functions defined in `.zshrc.d` do not exist in a non-interactive shell unless it sources the user's profile, which varies by harness. Executables on `PATH` always work. This is the structural half of the fix; the `hv-toolbelt` skill in Task 20 documents the other half — which helpers still need a TTY.

- [ ] **Step 1: Write the failing test**

Create `tests/bin/helpers.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  export REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  cd "$REPO" || exit 1
  git init -q -b main
  git config user.email t@t.t
  git config user.name Test
  git commit -q --allow-empty -m init
}

@test "gbd refuses to delete main" {
  run "$HV_ROOT/bin/gbd" main
  [ "$status" -eq 3 ]
  [[ "$stderr$output" == *"protected"* ]]
}

@test "gbd refuses to delete master" {
  run "$HV_ROOT/bin/gbd" master
  [ "$status" -eq 3 ]
}

@test "gbd refuses to delete develop" {
  run "$HV_ROOT/bin/gbd" develop
  [ "$status" -eq 3 ]
}

@test "gbd requires a branch name" {
  run "$HV_ROOT/bin/gbd"
  [ "$status" -eq 2 ]
  [[ "$stderr$output" == *"usage"* ]]
}

@test "gbd deletes a merged branch locally" {
  git branch feature
  run "$HV_ROOT/bin/gbd" feature
  [ "$status" -eq 0 ]
  run git branch --list feature
  [ "$output" = "" ]
}

@test "gbd -D force-deletes an unmerged branch" {
  git switch -q -c feature
  git commit -q --allow-empty -m work
  git switch -q main
  run "$HV_ROOT/bin/gbd" -D feature
  [ "$status" -eq 0 ]
}

@test "gprune runs without a remote and leaves main alone" {
  run "$HV_ROOT/bin/gprune"
  run git branch --list main
  [[ "$output" == *"main"* ]]
}

@test "helpers need no TTY" {
  run bash -c "'$HV_ROOT/bin/gbd' main < /dev/null"
  [ "$status" -eq 3 ]
}

@test "interactive helpers are not in bin" {
  for f in ff ffa fif gcof glogf j; do
    [ ! -e "$HV_ROOT/bin/$f" ]
  done
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/bin/helpers.bats
```

Expected: FAIL — `bin/gbd` does not exist.

- [ ] **Step 3: Write `bin/gbd`**

```bash
#!/usr/bin/env bash
# Delete a branch locally and on the remote. Safe for non-interactive use.
set -euo pipefail

force=""
if [ "${1:-}" = "-D" ]; then
  force="-D"
  shift
fi

branch="${1:-}"
if [ -z "$branch" ]; then
  echo "usage: gbd [-D] <branch-name>" >&2
  exit 2
fi

case "$branch" in
  main|master|develop)
    echo "refusing to delete protected branch: $branch" >&2
    exit 3
    ;;
esac

if [ -n "$force" ]; then
  git branch -D "$branch"
else
  git branch -d "$branch"
fi

git push origin --delete "$branch" 2>/dev/null || true
```

- [ ] **Step 4: Write `bin/gprune`**

```bash
#!/usr/bin/env bash
# Delete local branches whose upstream is gone. Safe for non-interactive use.
set -euo pipefail

git fetch --prune --prune-tags 2>/dev/null || true

current="$(git branch --show-current 2>/dev/null || true)"

git branch -vv | awk '/: gone]/{print $1}' | while read -r b; do
  [ -z "$b" ] && continue
  [ "$b" = "$current" ] && continue
  case "$b" in
    main|master|develop) continue ;;
  esac
  git branch -D "$b"
done
```

- [ ] **Step 5: Trim the shell fragment**

Edit `zsh/.zshrc.d/git.zsh`: delete the `gprune()` and `gbd()` function definitions. Keep `g`, `gbc`, `gco`, `gcof`, `glogf`, the `_gbd` completion and every `compdef` line — the completions still apply to the executables.

- [ ] **Step 6: Run the test to verify it passes**

```bash
chmod +x bin/gbd bin/gprune
bats tests/bin/helpers.bats
```

Expected: PASS, 9 tests.

- [ ] **Step 7: Commit**

```bash
shellcheck bin/gbd bin/gprune
git add bin/gbd bin/gprune zsh/.zshrc.d/git.zsh tests/bin/helpers.bats
git commit -m "refactor: move non-interactive git helpers to bin/"
```

---

## Task 19: Step 90 — verify, and the drift nudges

**Files:**
- Create: `setup/steps/90-check.sh`
- Create: `setup/lib/docs.sh`
- Test: `tests/steps/90-check.bats`

**Interfaces:**
- Consumes: `hv::config_get`, `hv::modules`
- Produces:
  - `HV_STEP_NAME="verify"`, scope `user`
  - `hv::docs_generate` — writes `docs/USAGE.md` from `docs/usage/*.md`
  - `hv::docs_current` — 0 when `docs/USAGE.md` matches the fragments

Two spec-required checks live here: `docs/USAGE.md` must match its source fragments, and untracked personal config with no overlay configured is drift, because it will not survive a machine wipe.

- [ ] **Step 1: Write the failing test**

Create `tests/steps/90-check.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  source "$HV_ROOT/setup/lib/docs.sh"
}

@test "docs_current is true for a freshly generated USAGE.md" {
  run hv::docs_current
  [ "$status" -eq 0 ]
}

@test "docs_current is false when a fragment changes" {
  echo "# drift" >> "$HV_ROOT/docs/usage/core.md"
  run hv::docs_current
  local rc="$status"
  git -C "$HV_ROOT" checkout -- docs/usage/core.md
  [ "$rc" -eq 1 ]
}

@test "check warns about untracked personal config with no overlay" {
  mkdir -p "$HV_CONFIG_HOME"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  source "$HV_ROOT/setup/steps/90-check.sh"
  run hv_step_run
  [[ "$stderr$output" == *"overlay"* ]]
}

@test "check does not warn when an overlay is configured" {
  mkdir -p "$HV_CONFIG_HOME" "$HOME/overlay"
  echo 'cask "chatgpt"' > "$HV_CONFIG_HOME/local.Brewfile"
  hv::config_set HV_OVERLAY "$HOME/overlay"
  source "$HV_ROOT/setup/steps/90-check.sh"
  run hv_step_run
  [[ "$stderr$output" != *"will not survive"* ]]
}

@test "check does not warn about an empty local.Brewfile" {
  mkdir -p "$HV_CONFIG_HOME"
  : > "$HV_CONFIG_HOME/local.Brewfile"
  source "$HV_ROOT/setup/steps/90-check.sh"
  run hv_step_run
  [[ "$stderr$output" != *"will not survive"* ]]
}

@test "step scope is user" {
  source "$HV_ROOT/setup/steps/90-check.sh"
  [ "$HV_STEP_SCOPE" = "user" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/steps/90-check.bats
```

Expected: FAIL — `setup/lib/docs.sh` does not exist.

- [ ] **Step 3: Write the docs library**

Create `setup/lib/docs.sh`:

```bash
#!/usr/bin/env bash
# docs/USAGE.md is generated from docs/usage/*.md so the cheatsheet, the
# browsable reference and the agent skill cannot disagree.

hv::docs_order() { printf '%s\n' core swift web python security; }

hv::docs_render() {
  local m file
  printf '# Usage Guide\n\n'
  printf '<!-- Generated from docs/usage/*.md by hv. Edit those, not this. -->\n\n'
  for m in $(hv::docs_order); do
    file="$HV_ROOT/docs/usage/$m.md"
    [ -f "$file" ] || continue
    cat "$file"
    printf '\n'
  done
}

hv::docs_generate() {
  hv::docs_render > "$HV_ROOT/docs/USAGE.md"
}

hv::docs_current() {
  [ -f "$HV_ROOT/docs/USAGE.md" ] || return 1
  hv::docs_render | diff -q - "$HV_ROOT/docs/USAGE.md" >/dev/null 2>&1
}

# Print only the fragments for the modules installed on this machine.
hv::docs_cheatsheet() {
  local want="${1:-}" m file
  for m in $(hv::docs_order); do
    file="$HV_ROOT/docs/usage/$m.md"
    [ -f "$file" ] || continue
    if [ -n "$want" ] && [ "$want" != "all" ]; then
      [ "$want" = "$m" ] || continue
    elif [ "$want" != "all" ]; then
      hv::module_enabled "$m" || continue
    fi
    cat "$file"
    printf '\n'
  done
}
```

- [ ] **Step 4: Load the docs library in `bin/hv`**

`90-check.sh` calls `hv::docs_current`, so `bin/hv` must source `docs.sh`.
Change the library loop:

```bash
for _lib in log link machine config prompt docs; do
```

Without this the verify step fails with "command not found" as soon as it is
wired into the runner.

- [ ] **Step 5: Write the verify step**

Create `setup/steps/90-check.sh`:

```bash
#!/usr/bin/env bash
# Final report. Untracked personal config with no overlay is drift: it will
# not survive a machine wipe and does not sync between a person's own Macs.

HV_STEP_NAME="verify"
HV_STEP_SCOPE="user"

hv::_untracked_personal_config() {
  local f
  for f in "${HV_CONFIG_HOME:-$HOME/.config/hv}/local.Brewfile"; do
    [ -s "$f" ] && return 0
  done
  return 1
}

hv_step_check() {
  hv::docs_current || return 1
  return 0
}

hv_step_run() {
  hv::step 90 "check"

  hv::docs_current || hv::warn "docs/USAGE.md is stale — run: hv cheatsheet --regenerate"

  local overlay
  overlay="$(hv::config_get HV_OVERLAY)"
  if hv::_untracked_personal_config && { [ -z "$overlay" ] || [ "$overlay" = "none" ]; }; then
    hv::warn "you have personal packages that will not survive a machine wipe"
    hv::log "Run 'hv overlay init' to track them in your own repo."
  fi

  hv::ok "checks complete"
  return 0
}
```

- [ ] **Step 6: Run the test to verify it passes**

Task 20 creates the `docs/usage/*.md` fragments, so run this suite again after Task 20 as well.

```bash
bats tests/steps/90-check.bats
```

Expected: PASS, 6 tests.

- [ ] **Step 7: Commit**

```bash
shellcheck -x setup/steps/90-check.sh setup/lib/docs.sh bin/hv
git add setup/steps/90-check.sh setup/lib/docs.sh bin/hv tests/steps/90-check.bats
git commit -m "feat: add verify step with docs and overlay drift checks"
```

---

## Task 20: Module usage docs and `hv cheatsheet`

**Files:**
- Create: `docs/usage/{core,swift,web,python,security}.md`
- Create: `docs/USAGE.md` (generated)
- Modify: `bin/hv` — replace the `cheatsheet)` dispatch line
- Test: `tests/docs/cheatsheet.bats`

**Interfaces:**
- Consumes: `hv::docs_cheatsheet`, `hv::docs_generate`, `hv::module_enabled`
- Produces: `hv cheatsheet [module|--all|--regenerate]`

`bin/hv` currently routes `cheatsheet` to the step runner, which is wrong — it is not a converge step. This task fixes that.

- [ ] **Step 1: Write the failing test**

Create `tests/docs/cheatsheet.bats`:

```bash
#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  hv::config_set HV_MODULES "core web"
  hv::config_load
}

@test "cheatsheet prints only installed modules" {
  run "$HV_ROOT/bin/hv" cheatsheet
  [[ "$output" == *"ripgrep"* ]]
  [[ "$output" != *"xcbeautify"* ]]
}

@test "cheatsheet --all prints every module" {
  run "$HV_ROOT/bin/hv" cheatsheet --all
  [[ "$output" == *"xcbeautify"* ]]
}

@test "cheatsheet accepts a module name" {
  run "$HV_ROOT/bin/hv" cheatsheet swift
  [[ "$output" == *"xcbeautify"* ]]
  [[ "$output" != *"ripgrep"* ]]
}

@test "USAGE.md is current" {
  source "$HV_ROOT/setup/lib/docs.sh"
  run hv::docs_current
  [ "$status" -eq 0 ]
}

@test "every module with a Brewfile has a usage fragment" {
  for m in core swift web python security; do
    [ -f "$HV_ROOT/docs/usage/$m.md" ]
  done
}

@test "core usage documents the interactive helpers" {
  for c in ff fif gcof glogf; do
    grep -q "\`$c\`" "$HV_ROOT/docs/usage/core.md"
  done
}

@test "core usage documents the bin helpers" {
  grep -q "gprune" "$HV_ROOT/docs/usage/core.md"
  grep -q "gbd" "$HV_ROOT/docs/usage/core.md"
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/docs/cheatsheet.bats
```

Expected: FAIL — `docs/usage/core.md` does not exist.

- [ ] **Step 3: Write the fragments**

Split the existing `USAGE.md` from `hyperspacemark/dotfiles` by module. Each fragment keeps its "when you would reach for this" framing rather than becoming a bare syntax table.

- `docs/usage/core.md` — shell, autosuggestions, completion, zoxide, `j`, `ff`, `ffa`, `fif`, `rg`, fzf keybindings, `bat`, `eza`, git aliases (`g`, `gbc`, `gco`, `gcof`, `glogf`, `gprune`, `gbd`), delta, `gh`, starship, Homebrew
- `docs/usage/swift.md` — `xcbeautify`, `swiftlint`, `swift format`, the `recipes` Makefile targets
- `docs/usage/web.md` — `fnm`, `pnpm`, `vercel`, `wrangler`, `supabase`, `railway`
- `docs/usage/python.md` — `pyenv`, `uv`
- `docs/usage/security.md` — `gitleaks`, `pre-commit`

Start each fragment with a `## <Module>` heading so the generated `USAGE.md` reads as one document.

- [ ] **Step 4: Fix the dispatcher**

In `bin/hv`, replace this line:

```bash
    cheatsheet) hv::cmd_cheatsheet "$@" ;;
```

for the existing:

```bash
    cheatsheet) hv::cmd_setup cheatsheet ;;
```

and add this function above `main` (Task 19 already added `docs` to the library loop):

```bash
hv::cmd_cheatsheet() {
  hv::config_load
  case "${1:-}" in
    --regenerate) hv::docs_generate; hv::ok "docs/USAGE.md regenerated" ;;
    --all) hv::docs_cheatsheet all ;;
    "") hv::docs_cheatsheet ;;
    *) hv::docs_cheatsheet "$1" ;;
  esac
}
```

`main` must pass through the remaining arguments; change the option loop to collect unrecognised arguments into a positional list and pass them to the command.

- [ ] **Step 5: Generate USAGE.md and run the tests**

```bash
bash -c '. setup/lib/log.sh; . setup/lib/config.sh; . setup/lib/docs.sh; HV_ROOT=$PWD hv::docs_generate'
bats tests/docs/cheatsheet.bats tests/steps/90-check.bats
```

Expected: PASS, 7 + 6 tests.

- [ ] **Step 6: Commit**

```bash
shellcheck bin/hv
git add docs/usage docs/USAGE.md bin/hv tests/docs/cheatsheet.bats
git commit -m "feat: add module-aware cheatsheet and generated usage reference"
```

---

## Task 21: The `hv-toolbelt` skill and the written guides

**Files:**
- Create: `claude/skills/hv-toolbelt/SKILL.md`
- Create: `docs/START-HERE.md`, `docs/ONBOARDING.md`, `docs/AGENTS.md`
- Test: `tests/docs/skill.bats`

**Interfaces:**
- Consumes: `docs/usage/*.md`
- Produces: the skill that step 80 links into `~/.claude/skills/`

The skill's highest-value content is the hazard list, not the command reference. An agent that runs `gcof` blocks forever on a TTY that does not exist.

- [ ] **Step 1: Write the failing test**

Create `tests/docs/skill.bats`:

```bash
#!/usr/bin/env bats

load ../helper

SKILL="$HV_ROOT/claude/skills/hv-toolbelt/SKILL.md"

@test "skill has frontmatter with name and description" {
  head -1 "$SKILL" | grep -q -- '---'
  grep -q '^name: hv-toolbelt' "$SKILL"
  grep -q '^description: ' "$SKILL"
}

@test "skill lists every interactive helper as unsafe" {
  for c in ff ffa fif gcof glogf j zi; do
    grep -q "$c" "$SKILL"
  done
  grep -qi "hang" "$SKILL"
}

@test "skill lists the bin helpers as safe" {
  grep -q "gprune" "$SKILL"
  grep -q "gbd" "$SKILL"
}

@test "skill points at the generated reference rather than duplicating it" {
  grep -q "docs/USAGE.md" "$SKILL"
}

@test "skill is short enough to stay cheap" {
  run wc -l < "$SKILL"
  [ "$output" -lt 120 ]
}

@test "START-HERE lists at most ten commands" {
  run grep -c '^| `' "$HV_ROOT/docs/START-HERE.md"
  [ "$output" -le 10 ]
}

@test "ONBOARDING covers the per-repo setup that hv clone does not automate" {
  grep -q "pre-commit install" "$HV_ROOT/docs/ONBOARDING.md"
  grep -q ".env.local" "$HV_ROOT/docs/ONBOARDING.md"
  grep -q "gh auth login" "$HV_ROOT/docs/ONBOARDING.md"
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/docs/skill.bats
```

Expected: FAIL — the skill does not exist.

- [ ] **Step 3: Write the skill**

Create `claude/skills/hv-toolbelt/SKILL.md`:

```markdown
---
name: hv-toolbelt
description: Use when running shell commands on a machine set up by hiddenvector/dotfiles - lists the custom git and search helpers available, and which of them will hang a non-interactive agent.
---

# Hidden Vector toolbelt

This machine is configured by [hiddenvector/dotfiles](https://github.com/hiddenvector/dotfiles).

## Never run these

Every one opens an fzf picker and blocks on a TTY. In a non-interactive shell
they hang until the tool call times out.

| Command | What it does | Use instead |
|---|---|---|
| `ff`, `ffa` | fuzzy file opener | `rg --files`, then Read |
| `fif` | fuzzy in-file search | `rg -n "pattern"` |
| `gcof` | fuzzy branch switcher | `git switch <branch>` |
| `glogf` | fuzzy git log | `git log --oneline` |
| `j` | fuzzy project picker | `cd` to the path |
| `zi` | interactive zoxide | `cd` to the path |

## Safe to run

| Command | What it does |
|---|---|
| `gprune` | delete local branches whose upstream is gone |
| `gbd [-D] <branch>` | delete a branch locally and on the remote; refuses main/master/develop |
| `g [args]` | `git status` with no arguments, otherwise proxies to git |
| `hv check` | report environment drift; mutates nothing |
| `hv cheatsheet [module]` | usage docs for what is installed here |

`gprune` and `gbd` are executables in `bin/`, not shell functions, so they work
in any shell. The interactive ones are zsh functions and only exist in a login
shell.

## Search preferences

- Prefer `rg` over `grep` and `find`. It respects `.gitignore` and is faster.
- `cat` is aliased to `bat` in interactive shells only. In scripts, use `cat`.

## Full reference

`docs/USAGE.md` in the dotfiles repo, or `hv cheatsheet` for just the modules
installed on this machine.
```

- [ ] **Step 4: Write the guides**

`docs/START-HERE.md` — a table of at most ten commands (`hv check`, `hv cheatsheet`, `g`, `ff`, `fif`, `j`, `z`, `ll`, `gbc`, `gprune`), each with one sentence on when to reach for it, then a pointer to `USAGE.md`.

`docs/ONBOARDING.md` — GitHub org access, `gh auth login`, registering the SSH signing key, Vercel/Railway/Supabase accounts, and per-repo setup for each client repo (`the-house`: `pre-commit install`, `.env.local` from the example, `fnm use`; `recipes`: `make help`; `mkw-data-api`: `npm install`, `wrangler dev`).

`docs/AGENTS.md` — the house convention for working with agents, distilled from
`recipes/AGENTS.md` and `the-house/CLAUDE.md`. Exact sections:

1. **What agents are for here** — agents draft and verify; humans decide.
2. **Before code** — brainstorm, then plan, then test-first. Link the
   superpowers skills by name.
3. **Per-repo context** — every client repo carries its own `AGENTS.md` or
   `CLAUDE.md`; read it before touching the repo. Table of the four repos and
   which file to read.
4. **Reviewing agent output** — what to check that agents habitually get wrong:
   unrun tests, silent scope changes, invented APIs.
5. **When to stop an agent** — repeated failed fixes, growing diff, confident
   claims without output.

- [ ] **Step 5: Run the test to verify it passes**

```bash
bats tests/docs/skill.bats
```

Expected: PASS, 7 tests.

- [ ] **Step 6: Commit**

```bash
git add claude/skills docs/START-HERE.md docs/ONBOARDING.md docs/AGENTS.md tests/docs/skill.bats
git commit -m "docs: add toolbelt skill, start-here and onboarding guides"
```

---

## Task 22: Bootstrap, README and CI

**Files:**
- Create: `bootstrap`, `README.md`, `.github/workflows/ci.yml`
- Test: `tests/bootstrap.bats`

**Interfaces:**
- Consumes: nothing — `bootstrap` runs before the repo exists
- Produces: the single-command first run

`bootstrap` stays thin: Command Line Tools, clone, `exec hv setup`. It duplicates no converge step, so a first run and a repair run take the identical code path.

- [ ] **Step 1: Write the failing test**

Create `tests/bootstrap.bats`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bats tests/bootstrap.bats
```

Expected: FAIL — `bootstrap` does not exist.

- [ ] **Step 3: Write `bootstrap`**

```bash
#!/usr/bin/env bash
# First run on a fresh Mac. Deliberately thin: Command Line Tools, clone,
# then hand off. Every converge step lives in `hv setup`, so a first run and
# a repair run take the identical path.
set -euo pipefail

REPO="https://github.com/hiddenvector/dotfiles"
DEST="$HOME/Developer/github.com/hiddenvector/dotfiles"

echo "Hidden Vector dotfiles — bootstrap"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "  Installing Command Line Tools (GUI prompt)…"
  xcode-select --install || true
  echo "  Rerun this once they finish installing."
  exit 1
fi

if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only
else
  mkdir -p "$(dirname "$DEST")"
  git clone "$REPO" "$DEST"
fi

exec "$DEST/bin/hv" setup "$@"
```

- [ ] **Step 4: Write the README**

`README.md` covers: what the repo is; the one-line install and the read-it-first alternative; the `hv` command table; the three layers; how to add a module; how overlays work; and a pointer to `docs/START-HERE.md`.

```markdown
## Install

```bash
curl -fsSL https://hiddenvector.studio/dotfiles | bash
```

Piping a script into bash asks you to trust it sight unseen. To read it first:

```bash
curl -fsSL https://hiddenvector.studio/dotfiles -o /tmp/hv-bootstrap && less /tmp/hv-bootstrap && bash /tmp/hv-bootstrap
```
```

- [ ] **Step 5: Write CI**

Create `.github/workflows/ci.yml`:

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install bats-core shellcheck
      - name: shellcheck
        run: shellcheck -x bin/hv bin/gbd bin/gprune bootstrap setup/lib/*.sh setup/steps/*.sh
      - name: bats
        run: bats --recursive tests/
```

- [ ] **Step 6: Run the whole suite**

```bash
chmod +x bootstrap
bats --recursive tests/
shellcheck -x bin/hv bin/gbd bin/gprune bootstrap setup/lib/*.sh setup/steps/*.sh
```

Expected: all suites PASS, shellcheck clean.

- [ ] **Step 7: Verify the two spec-level invariants by hand**

```bash
hv setup --dry-run
git status --porcelain
```

Expected: `git status` empty, nothing created in `$HOME`.

```bash
hv setup && hv setup
```

Expected: the second run reports every step converged and changes nothing.

- [ ] **Step 8: Commit**

```bash
git add bootstrap README.md .github/workflows/ci.yml tests/bootstrap.bats
git commit -m "feat: add bootstrap, README and CI"
```

---

## Task 23: Migrate the personal repo to an overlay

**Files:**
- Modify: `~/Developer/github.com/hyperspacemark/dotfiles` (a different repo)

This is the migration from the spec. It runs **last**, once the base is proven on at least one machine.

- [ ] **Step 1: Tag the last full-dotfiles state**

```bash
git -C ~/Developer/github.com/hyperspacemark/dotfiles tag -a v1-final 8a43218 -m "Last state as standalone dotfiles, before becoming an HV overlay"
```

- [ ] **Step 2: Push the tag**

```bash
git -C ~/Developer/github.com/hyperspacemark/dotfiles push origin v1-final
```

- [ ] **Step 3: Reduce the repo to the overlay contract**

Delete everything except the personal layer, then create `brew/personal.Brewfile` containing the two casks that do not belong in a company repo:

```ruby
cask "chatgpt"
cask "codex"
```

Create `zsh/../zshrc.d/personal.zsh` and `git/config` as needed, and rewrite `README.md` to explain the lineage: a full dotfiles repo from 2014 to 2026, now a personal overlay on `hiddenvector/dotfiles`.

- [ ] **Step 4: Verify the overlay is picked up**

```bash
hv setup --only overlay
hv setup --only packages
hv check
```

Expected: `chatgpt` and `codex` install from the overlay; `hv check` reports no untracked-personal-config warning.

- [ ] **Step 5: Commit and push**

```bash
git -C ~/Developer/github.com/hyperspacemark/dotfiles add -A
git -C ~/Developer/github.com/hyperspacemark/dotfiles commit -m "Become a Hidden Vector dotfiles overlay"
git -C ~/Developer/github.com/hyperspacemark/dotfiles push
```
