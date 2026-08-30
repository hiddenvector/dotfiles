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
    local backup
    backup="$dst.bak.$(date +%s)"
    hv::warn "backing up existing $dst -> $backup"
    hv::run mv "$dst" "$backup"
  fi

  hv::run ln -sfn "$src" "$dst"
  # hv::run is a no-op under HV_DRY_RUN=1 -- ln never actually ran, so
  # claiming "linked" would be a false success line in a dry-run preview.
  [ "${HV_DRY_RUN:-0}" = "1" ] || hv::ok "linked $dst"
}
