g() {
  if [[ $# -eq 0 ]]; then
    git status
  else
    git "$@"
  fi
}

gbc() {
  local branch="$1"
  if [[ -z "$branch" ]]; then
    echo "usage: gbc <branch-name>" >&2
    return 2
  fi

  git switch -c "$branch" || return $?

  git push -u origin "$branch"
}

gco() {
  if [[ -z "$1" ]]; then
    git branch
  else
    git switch "$@"
  fi
}

gcof() {
  local branch
  branch="$(git branch --all --format='%(refname:short)' \
    | sed 's|^remotes/||' \
    | sort -u \
    | fzf)" || return
  [[ -n "$branch" ]] || return
  git switch "$branch"
}

glogf() {
  git log --oneline --decorate --color=always \
    | fzf --ansi --no-sort --tiebreak=index \
          --preview 'git show --color=always {1}'
}

# gprune and gbd live in bin/ now — real executables, callable by anything
# without needing this file sourced. Completions for them stay here.

# Completion for gbd (adds -D + branch-name completion)
_gbd() {
  local -a opts
  opts=(-D)

  # first arg: offer -D and branch names
  if (( CURRENT == 2 )); then
    _describe -t options 'options' opts
    _git-branch
    return
  fi

  # after -D: offer branch names
  if [[ "${words[2]}" == "-D" ]]; then
    _git-branch
    return
  fi

  _git-branch
}
compdef _gbd gbd

compdef _git gbc=git-switch
compdef _git gco=git-switch
compdef _git gprune=git-fetch
compdef _git gcof=git-switch
