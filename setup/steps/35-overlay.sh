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
hv::_migrate_local() {
  local dir="$1" src
  [ "${HV_DRY_RUN:-0}" = "1" ] && return 0
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
      [ "${HV_DRY_RUN:-0}" = "1" ] && return 0
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
  [ "${HV_DRY_RUN:-0}" = "1" ] && return 0
  hv::ok "created github.com/$default_repo"
  return 0
}
