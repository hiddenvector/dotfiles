#!/usr/bin/env bash
# Node belongs to fnm, never to Homebrew. Python belongs to pyenv.

export HV_STEP_NAME="toolchains"
export HV_STEP_SCOPE="user"

hv_step_check() {
  if hv::module_enabled web; then
    command -v fnm >/dev/null 2>&1 || return 1
    # The lts-latest alias only exists once fnm default lts-latest has run
    fnm list 2>/dev/null | grep -q 'lts-latest' || return 1
  fi
  if hv::module_enabled python; then
    command -v pyenv >/dev/null 2>&1 || return 1
    # Verify pyenv global is set to 3.13.x
    case "$(pyenv version-name 2>/dev/null)" in
      3.13*) ;;
      *) return 1 ;;
    esac
  fi
  return 0
}

hv_step_run() {
  hv::step 70 "toolchains"

  if hv::module_enabled web; then
    local web_ok=0
    hv::run fnm install --lts || { hv::warn "fnm install --lts failed"; web_ok=1; }
    hv::run fnm default lts-latest || { hv::warn "fnm default lts-latest failed"; web_ok=1; }
    hv::run npm install -g pnpm vercel || { hv::warn "npm install -g pnpm vercel failed"; web_ok=1; }
    [ "$web_ok" -eq 0 ] && [ "${HV_DRY_RUN:-0}" != "1" ] && hv::ok "Node (fnm) + pnpm, vercel"
  fi

  if hv::module_enabled python; then
    local python_ok=0
    hv::run pyenv install --skip-existing 3.13 || { hv::warn "pyenv install --skip-existing 3.13 failed"; python_ok=1; }
    hv::run pyenv global 3.13 || { hv::warn "pyenv global 3.13 failed"; python_ok=1; }
    [ "$python_ok" -eq 0 ] && [ "${HV_DRY_RUN:-0}" != "1" ] && hv::ok "Python (pyenv)"
  fi

  return 0
}
