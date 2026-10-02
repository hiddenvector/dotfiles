# Homebrew

eval "$(/opt/homebrew/bin/brew shellenv)"

# Docker Desktop

export PATH="$PATH:/Users/markadams/.docker/bin"

# Local bin

export PATH="$HOME/.local/bin:$PATH"

# Version Managers

command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init --path)"
command -v fnm   >/dev/null 2>&1 && eval "$(fnm env)"

# Locale

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Editor

export EDITOR="code --wait"
export VISUAL="$EDITOR"

# zsh ships a `log` builtin (from its login-watch feature) that shadows /usr/bin/log. Apple
# disables it in /etc/zshrc, which only interactive shells read; non-interactive login shells
# (scripts, agents, `zsh -lc`) still get the builtin. Disable it for every login shell here.
disable log 2>/dev/null
