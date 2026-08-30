## Core

Always installed, regardless of which modules a machine has enabled. This is
the shell, prompt, and git layer everything else sits on top of.

### Shell

- History is shared live across every open terminal (`SHARE_HISTORY`), kept
  free of consecutive duplicates and stray blank lines, and holds the last
  10,000 commands (`~/.zsh_history`).
- `autocd` — type a directory's name on its own and zsh `cd`s into it, no
  `cd` needed.
- Tab-completion opens a selectable menu (`zstyle ':completion:*' menu
  select`) and matches case-insensitively; `Tab` cycles forward through
  matches and `Shift-Tab` cycles back (`^I` / `^[[Z` are bound to
  `menu-complete` / `reverse-menu-complete`). The completion cache is kept
  in `~/.zsh/cache` and only rebuilt (`compinit`, checking for insecure
  directories) when the dump is more than a day old; otherwise it loads
  fast via `compinit -C`.
- **zsh-autosuggestions** — as you type, the rest of a previously-run
  command that matches is greyed in inline. Press `Ctrl-Space` to accept it
  (`^ ` is rebound from its default to `autosuggest-accept`).
- **zsh-syntax-highlighting** — colors the command line as you type
  (valid commands green, invalid ones red) so typos are visible before you
  hit enter. No keybindings; it just runs.

### Finding your way around: zoxide, `j`, fzf

- `z <query>` / `zi` — zoxide's own jump commands, from `zoxide init zsh`
  with no `--cmd` override, so they keep their default names. `z` jumps
  straight to the best-ranked directory match by your visit frecency;
  **`zi` is interactive** — it opens an fzf picker over ranked matches
  instead of jumping straight there, and needs a TTY.
- `j [query]` — **interactive, needs a TTY.** This is *not* zoxide frecency
  — it is a repo picker defined in `zsh/.zshrc.d/fzf.zsh`: it `find`s every
  `.git` directory under `~/Developer` (up to 5 levels deep), strips the
  `.git` suffix, and hands the list to fzf. Anything you pass as arguments
  seeds fzf's initial query, to narrow the list before you see it. Reach
  for this over `z` when you want to jump to a project you haven't
  necessarily visited recently, or when you only remember part of the name.
- `ff` — **interactive, needs a TTY.** Fuzzy-open a file with `$EDITOR`
  (`code --wait` by default). Inside a git repo it lists tracked and
  untracked-but-not-ignored files (`git ls-files -co --exclude-standard`);
  outside one it falls back to `rg --files` over hidden files too, skipping
  `.git`, `.build`, and `DerivedData`. Either way the fzf window previews
  the file with `bat` as you move the selection.
- `ffa` — **interactive, needs a TTY.** Like `ff`, but always walks the
  whole tree with plain `find` regardless of git status — use it when a
  file you want is gitignored and `ff` won't show it.
- `fif <text>` — **interactive, needs a TTY.** "Find in files": greps the
  tree with `rg` (again skipping `.git`, `.build`, `DerivedData`) and pipes
  matches into fzf, previewing the matching line with `bat`. Press `Enter`
  to open the selected match at the exact line in `$EDITOR`
  (`code --wait --goto file:line`). Requires a query argument; run with
  none and it prints a usage message and exits 2.
- `rg` (ripgrep) — the search engine underneath `ff`, `fif`, and fzf's own
  file-listing widgets. Reach for it directly for one-off greps outside
  those helpers, or when you want ripgrep's own flags (`-t`, `-g`, `-A/-B`,
  etc.) rather than the fzf wrapper.
- fzf's own keybindings (from `source <(fzf --zsh)`) — `Ctrl-T` fuzzy-inserts
  a file path at the cursor (using `rg --files --hidden --no-messages
  --glob '!.git'` as the source), `Ctrl-R` fuzzy-searches shell history, and
  `Alt-C` `cd`s into a fuzzy-picked subdirectory. Because macOS maps
  Option-C to the `ç` character rather than a literal Alt-C, this repo also
  binds `ç` directly to `fzf-cd-widget` so Option-C works as expected. The
  fzf window itself is themed once, globally, via `FZF_DEFAULT_OPTS`
  (40%-height, reversed layout, bordered, inline info, preview pane on the
  right 60%).

### Reading files: `bat`, `eza`

- `bat` — `cat` is aliased to `bat --paging=never`, so plain `cat file`
  already gets you syntax highlighting and line numbers; it is also what
  powers every fzf preview pane above.
- `eza` replaces the built-in file listers:
  - `ls` — `eza --group-directories-first`, a drop-in `ls` with directories
    sorted to the top.
  - `ll` — `eza -la --git`, a long listing that also shows each file's git
    status in a column.
  - `lt` — `eza --tree`, a recursive tree view of the current directory.

### Git

- `g` — with no arguments runs `git status`; with arguments it proxies
  straight to `git`, so `g log`, `g add -p`, `g switch main`, etc. all work
  exactly as their `git` equivalents. It exists purely to save keystrokes.
- `gbc <branch-name>` — create a branch and push it upstream in one step:
  `git switch -c <branch>` followed by `git push -u origin <branch>`. Use
  it when starting new work you know you'll want tracked on the remote
  immediately.
- `gco [branch...]` — with no arguments, lists local branches (`git
  branch`); with arguments, proxies to `git switch`. It's `g switch` with a
  shorter name and a friendlier no-args behavior.
- `gcof` — **interactive, needs a TTY.** Fuzzy-pick a branch (local or
  remote, deduplicated) via fzf and `git switch` to it. Reach for this
  instead of `gco` when you can't remember the exact branch name.
- `glogf` — **interactive, needs a TTY.** Browse `git log --oneline
  --decorate` through fzf, with a preview pane running `git show` on the
  highlighted commit. Good for scanning history visually rather than
  paging through `git log` in the terminal.
- `gprune` (`bin/gprune`) — a real executable, not a shell function, so it
  works from any script or tool without the zsh config being loaded. It
  fetches with `--prune --prune-tags`, then deletes every local branch
  whose upstream is gone (`git branch -vv` reporting `: gone]`), skipping
  the branch you're currently on and always refusing to touch `main`,
  `master`, or `develop`. Non-interactive and safe to run unattended.
- `gbd [-D] <branch-name>` (`bin/gbd`) — also a real executable. Deletes a
  branch both locally and on `origin` (`git branch -d`/`-D` then `git push
  origin --delete`, the latter ignored if the branch was never pushed).
  Refuses outright to delete `main`, `master`, or `develop`, even with
  `-D`. Non-interactive and safe to run unattended.
  - Tab-completion is wired for all of these: `gbd` offers `-D` plus branch
    names, and `gbc`/`gco`/`gcof`/`gprune` complete like their underlying
    `git switch`/`git fetch` commands.
- **delta** — configured as git's pager (`core.pager = delta`) and diff
  filter (`interactive.diffFilter = delta --color-only`), with side-by-side
  view and file navigation turned on. Every `git diff`, `git show`, and `g
  diff` you run gets delta's syntax-highlighted, side-by-side rendering for
  free — no separate invocation needed.
- **gh** — the GitHub CLI. Besides using it directly (`gh pr create`, `gh
  issue list`, ...), this repo's `~/.gitconfig` wires `gh auth
  git-credential` in as git's credential helper for `github.com` and
  `gist.github.com`, so HTTPS git operations authenticate through your `gh`
  login rather than prompting for a password or token.
- A few other git defaults worth knowing about: `pull.rebase` and
  `rebase.autoStash` are on (a plain `git pull` rebases and stashes/restores
  your dirty work around it automatically), merge conflicts render in
  `zdiff3` style, commits and tags are signed with your SSH key
  (`gpg.format = ssh`), and `push.autoSetupRemote` means a first `git push`
  on a new branch doesn't need `-u`.

### Prompt

- **starship** renders the prompt: current directory (bold blue, truncated
  to the repo root when inside one), the current git branch (⎇ symbol,
  bold purple), git status flags and ahead/behind count (bold yellow), and
  — only when a command took at least 2 seconds — how long it ran (bold
  yellow). It's silent and adds nothing when none of that applies, so the
  prompt stays short on a clean repo.

### Homebrew

- **Homebrew** is the package manager `hv setup` uses to install everything
  in this module's (and every other enabled module's) `Brewfile` — `brew
  bundle --file brew/<module>.Brewfile`. Two more core pieces come from it
  at runtime, in different ways: Homebrew's Zsh completions directory is
  hardcoded as `/opt/homebrew/share/zsh/site-functions` and added to
  `fpath` directly, since this repo targets Apple Silicon Macs only — it is
  not derived from `brew --prefix`. zsh-autosuggestions and
  zsh-syntax-highlighting, by contrast, *are* located via
  `BREW_PREFIX="${BREW_PREFIX:-$(brew --prefix)}"` and sourced from
  wherever that resolves, rather than vendored into this repo.

### `hv` itself

- `hv setup` — converge this machine to the state declared by its config
  and the modules you've enabled; safe to re-run any time.
- `hv check` — report drift without changing anything; exits 1 if the
  machine has drifted from the declared state (including a stale
  `docs/USAGE.md` — see `hv cheatsheet --regenerate` below).
- `hv update` — `git pull --ff-only` this repo, then `hv setup`.
- `hv identity` / `hv machine` — re-run just the identity or
  machine-name/module-selection step, without a full `hv setup`.
- `hv overlay init` — create and wire up a personal overlay repo for
  config that shouldn't live in this shared repo.
- `hv cheatsheet [module|--all|--regenerate]` — print this usage
  documentation. With no argument, prints only the fragments for modules
  enabled on this machine; `--all` prints every module's fragment
  regardless of what's enabled; a module name (e.g. `hv cheatsheet swift`)
  prints just that module's fragment even if it isn't enabled here;
  `--regenerate` rewrites `docs/USAGE.md` from the current fragments
  instead of printing anything.
- `--only <name>`, `--dry-run`, `--yes` — flags accepted by the
  convergence-related commands above: run a single named step, preview
  changes without making them, or accept defaults without prompting.
