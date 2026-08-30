#!/usr/bin/env bash
# Identity is per-account and travels across a person's machines.
# Signing keys are per-account per-machine and never travel.

export HV_STEP_NAME="identity"
export HV_STEP_SCOPE="user"

HV_GIT_CONFIG_HOME="${HV_GIT_CONFIG_HOME:-$HOME/.config/git}"

hv::_signing_key() {
  printf '%s\n' "$HOME/.ssh/id_ed25519_signing_$(hv::machine_name)"
}

hv_step_check() {
  [ -f "$HV_GIT_CONFIG_HOME/identity" ] && [ -f "$(hv::_signing_key)" ]
}

hv::_gh_authed() { gh auth status >/dev/null 2>&1; }

hv::_gh_field() {
  local v
  v="$(gh api user --jq "$1" 2>/dev/null || true)"
  [ "$v" = "null" ] && v=""
  printf '%s\n' "$v"
}

hv::_default_email() {
  local email id login
  email="$(hv::_gh_field .email)"
  if [ -z "$email" ]; then
    id="$(hv::_gh_field .id)"
    login="$(hv::_gh_field .login)"
    [ -n "$login" ] && email="${id}+${login}@users.noreply.github.com"
  fi
  printf '%s\n' "$email"
}

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

  # Dry-run mode: state what we would do and exit early. Every question
  # below (name, email, whether to upload a new signing key, whether to use
  # a different email for Hidden Vector repos) is a real prompt that blocks
  # on stdin -- a preview must never reach one.
  if [ "${HV_DRY_RUN:-0}" = "1" ]; then
    hv::log "would prompt for name and email"
    hv::log "would generate a signing key for this machine if it has none"
    hv::log "would prompt to upload the signing key to GitHub"
    hv::log "would write $HV_GIT_CONFIG_HOME/identity"
    return 0
  fi

  hv::_gh_authed || hv::run gh auth login

  local name email hv_email key
  name="$(hv::ask "Name" "$(hv::_gh_field .name)")"
  email="$(hv::ask "Email" "$(hv::_default_email)")"

  if [ -z "$email" ]; then
    hv::warn "email cannot be empty — cannot write identity file"
    return 0
  fi

  key="$(hv::_signing_key)"
  if [ ! -f "$key" ]; then
    hv::log "No signing key for this machine. Generating one."
    hv::log "(One key per machine — private keys never move between Macs.)"
    hv::run mkdir -p "$HOME/.ssh"
    hv::run ssh-keygen -t ed25519 -N "" -C "$(hv::machine_name) signing" -f "$key"

    if hv::confirm_always "Upload this signing key to your GitHub account?"; then
      if hv::run gh ssh-key add "$key.pub" --type signing \
           --title "$(hv::machine_name) (signing)"; then
        [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "uploaded to GitHub"
      else
        hv::warn "upload failed — add it manually:"
        hv::log "  gh ssh-key add $key.pub --type signing --title \"$(hv::machine_name) (signing)\""
      fi
    else
      hv::warn "not uploaded — commits will not verify until you add it:"
      hv::log "  gh ssh-key add $key.pub --type signing --title \"$(hv::machine_name) (signing)\""
    fi
    [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "$key"
  else
    [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "signing key present"
  fi

  hv::_write_identity "$HV_GIT_CONFIG_HOME/identity" "$name" "$email" "$key"

  if hv::confirm "Different email for Hidden Vector client repos?" n; then
    hv_email="$(hv::ask "HV email" "$email")"
    hv::_write_identity "$HV_GIT_CONFIG_HOME/identity.hv" "$name" "$hv_email" "$key"
    [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "includeIf gitdir:~/Developer/github.com/hiddenvector/"
  fi

  hv::_rebuild_allowed_signers "$email"
  return 0
}
