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
| `j` | fuzzy repo picker over `~/Developer` (not zoxide) | `cd` to the path |
| `zi` | interactive zoxide picker | `z <query>` or `cd` to the path |

## Safe to run

| Command | What it does |
|---|---|
| `gprune` | delete local branches whose upstream is gone |
| `gbd [-D] <branch>` | delete a branch locally and on the remote; refuses main/master/develop |
| `g [args]` | `git status` with no arguments, otherwise proxies to git |
| `hv check` | report environment drift; mutates nothing |
| `hv cheatsheet [module]` | usage docs for what is installed here |

`gprune` and `gbd` are real executables in `bin/`, not zsh functions, so they
work in any shell, scripted or interactive. Every command in the "never run"
table above is a zsh function defined in `zsh/.zshrc.d/` and only exists in a
login shell with a TTY attached.

## Search preferences

- Prefer `rg` over `grep` and `find`. It respects `.gitignore` and is faster.
- `cat` is aliased to `bat` in interactive shells only (see `zsh/.zshrc`). In
  scripts and non-interactive agent shells, plain `cat` runs instead.

## Full reference

`docs/USAGE.md` in the dotfiles repo, or `hv cheatsheet` for just the modules
installed on this machine.
