## Core

Always installed, regardless of which modules a machine has enabled.

- `j [query]` — fzf picker over every git repo under `~/Developer` (finds
  `.git` directories up to 5 levels deep) and `cd`s into the one you pick.
  Any arguments are passed to fzf as the initial query, to narrow the list
  before you see it.
- `g` — with no arguments, runs `git status`. With arguments, proxies
  straight to `git`, so `g log`, `g add -p`, etc. all work as-is.
