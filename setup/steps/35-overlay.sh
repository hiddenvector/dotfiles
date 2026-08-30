#!/usr/bin/env bash
# An overlay is a person's own layer on top of the shared base. Without one,
# personal config lands in untracked files that neither survive a machine wipe
# nor sync between a person's own Macs.
#
# Must run after step 30 (needs gh auth) and before step 40 (the overlay's
# git/config is included when the gitconfig is linked).

export HV_STEP_NAME="overlay"
export HV_STEP_SCOPE="user"

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
# Step scripts have no `set -e`, so an unchecked append followed by an
# unconditional `rm -f` would delete the user's only copy of their config if
# the append failed (overlay dir not writable, disk full, ...). The delete
# is gated on the append actually succeeding.
hv::_migrate_local() {
  local dir="$1" src
  [ "${HV_DRY_RUN:-0}" = "1" ] && return 0

  src="${HV_CONFIG_HOME:-$HOME/.config/hv}/local.Brewfile"
  if [ -s "$src" ]; then
    if cat "$src" >> "$dir/brew/personal.Brewfile"; then
      hv::run rm -f "$src"
      hv::ok "moved local.Brewfile into the overlay"
    else
      hv::warn "could not write $dir/brew/personal.Brewfile — leaving $src where it is"
    fi
  fi

  # local.zsh is only ever appended here, never deleted -- nothing else in
  # this codebase owns or later removes it the way the Brewfile is owned by
  # this migration -- so there is no delete to gate on success. Still warn
  # if the append itself fails, for the same reason as above.
  src="$HOME/.zshrc.d/local.zsh"
  if [ -s "$src" ] && ! grep -q '^# Machine-specific' "$src"; then
    if cat "$src" >> "$dir/zshrc.d/personal.zsh"; then
      hv::ok "moved local.zsh into the overlay"
    else
      hv::warn "could not write $dir/zshrc.d/personal.zsh — leaving $src where it is"
    fi
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
      [ "${HV_DRY_RUN:-0}" = "1" ] && return 0
    fi
    hv::ok "$configured"
    return 0
  fi

  # Dry-run mode: everything past this point either prompts (whether to
  # adopt or create an overlay, its repo name, its visibility) or shells
  # out to `gh` for real to compute what to offer -- a preview must do
  # neither, so state the intent and stop here.
  if [ "${HV_DRY_RUN:-0}" = "1" ]; then
    hv::log "would prompt to adopt or create a personal overlay repo"
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
      [ "${HV_DRY_RUN:-0}" = "1" ] && return 0
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

  # Every one of these can fail for real reasons (name taken, no network,
  # disk full, ...) and none of it is guarded by `set -e`. Each step's exit
  # status is checked explicitly, following the convention already
  # established in setup/steps/30-identity.sh: check, warn, print the manual
  # command, stop -- never scaffold, migrate, or claim `created` for a repo
  # that is not actually in the state that implies.
  #
  # Note: hv::run always returns 0 while HV_DRY_RUN=1 (it prints "would run"
  # instead of executing), so none of the "if ! hv::run ...; then" branches
  # below can be taken during a dry run -- they only fire on a real failure.
  if ! hv::run gh repo create "$default_repo" "--$visibility" \
       --description "Personal Hidden Vector dotfiles overlay"; then
    hv::warn "could not create $default_repo — nothing was scaffolded or recorded"
    hv::log "  gh repo create $default_repo --$visibility --description \"Personal Hidden Vector dotfiles overlay\""
    return 0
  fi

  if ! hv::run git clone "https://github.com/$default_repo" "$dir"; then
    hv::warn "created github.com/$default_repo, but the local clone failed"
    hv::log "  git clone https://github.com/$default_repo $dir"
    hv::log "Re-run 'hv overlay init' — it will offer to adopt the repo that already exists."
    return 0
  fi

  # The repo and the local clone both genuinely exist now, regardless of
  # whether scaffolding below succeeds -- record it so a re-run's case 1
  # (or case 2, if this run is retried from scratch) sees the true state.
  hv::config_set HV_OVERLAY "$dir"
  hv::config_set HV_OVERLAY_URL "https://github.com/$default_repo"

  hv::_scaffold_overlay "$dir"
  hv::_migrate_local "$dir"

  if ! hv::run git -C "$dir" add -A; then
    hv::warn "created and cloned github.com/$default_repo, but staging the scaffold failed"
    hv::log "  git -C $dir add -A"
    return 0
  fi

  if ! hv::run git -C "$dir" commit -m "Scaffold personal overlay"; then
    hv::warn "created and cloned github.com/$default_repo, but committing the scaffold failed"
    hv::log "  git -C $dir commit -m \"Scaffold personal overlay\""
    return 0
  fi

  if ! hv::run git -C "$dir" push -u origin HEAD; then
    hv::warn "created github.com/$default_repo and scaffolded it locally, but the push failed"
    hv::log "  git -C $dir push -u origin HEAD"
    return 0
  fi

  [ "${HV_DRY_RUN:-0}" = "1" ] && return 0
  hv::ok "created github.com/$default_repo"
  return 0
}
