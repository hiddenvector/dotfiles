# Usage Guide

<!-- Generated from docs/usage/*.md by hv. Edit those, not this. -->

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
  bundle --file brew/<module>.Brewfile`. It's also where two more core
  pieces come from at runtime: `brew --prefix`'s `share/zsh/site-functions`
  is added to `fpath` for Homebrew-installed completions, and
  zsh-autosuggestions/zsh-syntax-highlighting above are sourced straight
  out of the Homebrew prefix rather than vendored into this repo.

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

## Swift

Xcode and Swift-package tooling. Enable this module on machines that build
Apple-platform projects (this repo's Brewfile comment calls out `recipes` as
the consumer).

- `xcbeautify` — pipes `xcodebuild`'s notoriously verbose, hard-to-scan
  output into a compact, color-coded stream (one line per compile step,
  clear pass/fail markers). Reach for it any time you're driving
  `xcodebuild` from the command line: `xcodebuild build | xcbeautify`,
  `xcodebuild test | xcbeautify`, and so on — it does not change what
  `xcodebuild` does, only how readable watching it is.
- `swiftlint` — static analysis and style linting for Swift source. Run
  `swiftlint` (or `swiftlint lint`) from inside a Swift project to catch
  style violations and common mistakes before review; `swiftlint
  --fix` auto-corrects what it safely can. This repo installs the tool but
  does not ship a `.swiftlint.yml` of its own — each consuming project
  supplies its own rules.
- `swift format` — the formatter built into the Swift toolchain itself
  (shipped with Xcode's `swift` command, not a separate Homebrew package),
  invoked as a subcommand: `swift format lint` checks formatting without
  changing files, `swift format format -i` rewrites files in place. Use it
  to keep a codebase's formatting consistent without hand-tuning
  whitespace in review.

## Web

Node and web-deployment tooling. Serves this org's web projects (the-house,
mkw-data-api, hiddenvector.studio, per the Brewfile comment).

- `fnm` — Node version manager (Homebrew package `fnm`; Node itself is
  deliberately never installed via Homebrew, only through fnm). This
  repo's `hv setup` runs `fnm install --lts` and `fnm default lts-latest`
  for you, and both `.zprofile` and `.zshrc` `eval "$(fnm env ...)"` so the
  right Node is on `PATH` in every shell — `.zshrc` additionally passes
  `--use-on-cd`, so `cd`ing into a project with an `.nvmrc`/`.node-version`
  switches Node versions automatically. Use `fnm use <version>` or `fnm
  install <version>` directly when a project needs something other than
  the default LTS.
- `pnpm` — the package manager this org standardizes on for JS/TS
  projects. Not a Homebrew formula: it's installed globally via `npm
  install -g pnpm vercel` as part of `hv setup`'s toolchains step. Use it
  in place of `npm`/`yarn` (`pnpm install`, `pnpm run dev`, `pnpm add
  <pkg>`) in any project that has a `pnpm-lock.yaml`.
- `vercel` — the Vercel CLI, installed alongside `pnpm` in the same `npm
  install -g` step above. Reach for it to preview a deploy from your
  machine (`vercel`), ship to production (`vercel --prod`), or pull a
  project's environment variables locally (`vercel env pull`).
- `supabase` — the Supabase CLI (Homebrew tap `supabase/tap/supabase`).
  Use it for local Postgres/Supabase development against a project: `supabase
  start` to run the stack locally, `supabase db diff`/`migration new` to
  manage schema migrations, `supabase functions deploy` for edge
  functions.
- `railway` — the Railway CLI (Homebrew formula `railway`), for deploying
  and managing services on Railway: `railway up` to deploy the current
  directory, `railway logs`/`railway status` to check on a running
  service, `railway run` to execute a command with that project's
  environment variables injected.
- `jq` — a command-line JSON processor. Reach for it whenever a CLI in
  this module (or `curl` against an API) hands you JSON you need to
  filter, reshape, or pull a single field out of, e.g. `vercel ... | jq
  '.deployments[0].url'`.

## Python

Python tooling. Serves the-house's FastAPI backend, per the Brewfile
comment.

- `pyenv` — Python version manager. This repo's `hv setup` runs `pyenv
  install --skip-existing 3.13` and `pyenv global 3.13` for you, and both
  `.zprofile` (`pyenv init --path`, which only needs to adjust `PATH`) and
  `.zshrc` (`pyenv init -`, which also wires up shell completion and the
  `pyenv` shell function) `eval` its init output. Use `pyenv install
  <version>` / `pyenv local <version>` directly when a project pins a
  different Python.
- `uv` — a fast drop-in replacement for `pip`/`venv`/`pip-tools`. Reach for
  it instead of `pip` for everyday work: `uv venv` to create a virtualenv,
  `uv pip install <pkg>` to install into it (much faster than `pip
  install`), or `uv run <script>` to run a script with its dependencies
  resolved on the fly.

## Security

Secret-scanning and git-hook tooling. Serves the-house, whose
`.pre-commit-config.yaml` runs gitleaks, per the Brewfile comment.

- `gitleaks` — scans a repo's tracked files and git history for
  accidentally committed secrets (API keys, tokens, credentials). Run
  `gitleaks detect` to scan the current repo, or `gitleaks protect
  --staged` to check only what's about to be committed. In practice you'll
  usually meet it through `pre-commit` below rather than invoking it
  directly.
- `pre-commit` — the framework that installs and runs git hooks declared
  in a project's `.pre-commit-config.yaml` (which is what wires `gitleaks`
  in for the-house). Run `pre-commit install` once per clone to activate
  the hooks, and `pre-commit run --all-files` to run every configured hook
  against the whole tree on demand (useful the first time you install it
  in an existing repo, or after changing the config).

