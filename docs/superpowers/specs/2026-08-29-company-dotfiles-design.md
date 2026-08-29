# Hidden Vector dotfiles — design

Date: 2026-08-29
Status: approved, not yet implemented
Repo: github.com/hiddenvector/dotfiles (public)

## Problem

`hyperspacemark/dotfiles` is a good personal setup that three things now break:

1. **Identity is baked into tracked files.** `.gitconfig` and `gitconfig.work` both
   hardcode a name, email and signing key path. Anyone else cloning the repo either
   commits as Mark Adams or edits tracked files and carries a permanent local diff.
2. **The `--personal` / `--work` profile split encodes the wrong axis.** It exists to
   model one person's day job versus their side work. The real axis is the *machine*:
   the same person runs the same environment on several Macs, and a different
   environment on a managed corporate Mac.
3. **`install.sh` is a one-shot script, not a converge tool.** It exits on the first
   pre-existing non-symlink and has no way to report what is out of sync. There is no
   answer to "my environment is weird, fix it".

Meanwhile the Hidden Vector client repos need tooling the Brewfile does not install:
`gitleaks` and `pre-commit` (the-house), the Supabase CLI (the-house), a Python
toolchain for the FastAPI backend (the-house), and Swift/Xcode tooling (recipes).

## Goals

- Anyone in the org clones the repo and gets a working environment without editing
  a tracked file.
- One person runs the same environment across several Macs, with only genuine
  differences configured per machine.
- Multiple macOS accounts coexist on one Mac without interfering.
- Setup is re-runnable as a repair tool, not just a first-run installer.
- New engineers — and their coding agents — are put on rails toward the way
  Hidden Vector works.

## Non-goals

- **Immutability in the Nix sense.** Bash plus Homebrew cannot give reproducible
  builds or atomic rollback. What this delivers is *convergence*: idempotent steps,
  declared state in files, and drift detection. If true immutability is ever wanted,
  the answer is nix-darwin and a rewrite — not a more elaborate bash script. It is
  explicitly rejected here as hostile to someone learning to code agentically.
- **Per-project setup automation** (`hv clone`, `hv doctor <repo>`). The client repos
  are too heterogeneous — a Vite web app and a visionOS app share almost no setup —
  so any default today would be a guess that rots. Deferred until the pattern is
  visible across more repos. Covered as prose in `docs/ONBOARDING.md`.
- **Shipping a VS Code `settings.json`.** Editor configuration is personal; mandating
  it is how shared dotfiles breed resentment. Extensions are shared, settings are not.
- **Pinning Homebrew formula versions.** Fights Homebrew's model for little benefit.
- **Pruning unmanaged packages by default.** `brew bundle --cleanup` stays opt-in.

---

## Architecture

### Three layers

The core fix is separating what is shared from what is personal from what is
machine-specific.

| Layer | Location | Scope | Tracked |
|---|---|---|---|
| Shared config | this repo | everyone, everywhere | yes |
| User config | `~/.config/hv/config` | one account | no |
| Machine facts | derived from the system | one machine | n/a |

**Machine facts are derived, never stored.** Machine name comes from `scutil
--get ComputerName`; managed status from `profiles status -type enrollment`; arch and
admin rights from the system. Storing them per-account would mean two accounts on the
same Mac holding two copies of the same fact, free to drift. The system is the source
of truth.

`~/.config/hv/config` therefore holds only genuine user preferences:

```sh
HV_MODULES="core swift web python security apps"
HV_OVERLAY=""              # optional path to an overlay repo
HV_RESTRICTED=""           # override if MDM auto-detect is wrong
```

Adjacent untracked files, created as stubs by setup:

- `~/.config/hv/local.Brewfile` — personal packages (e.g. `cask "chatgpt"`)
- `~/.zshrc.d/local.zsh` — machine-specific shell config
- `~/.secrets` — tokens, `chmod 600`
- `~/.config/git/identity` — name, email, signing key

### Git identity

The tracked gitconfig contains **zero identity** and ends with:

```
[include]
    path = ~/.config/git/identity
```

For people who mix personal and client work, setup optionally adds:

```
[includeIf "gitdir:~/Developer/github.com/hiddenvector/"]
    path = ~/.config/git/identity.hv
```

This uses git's own native mechanism. No templating engine, no rendered files that
drift from the repo.

### Step scope: `system` vs `user`

Every converge step is tagged. This is what makes multiple accounts on one Mac work.

| Scope | Steps |
|---|---|
| `system` | Touch ID PAM config, machine name, Homebrew prefix |
| `user` | identity, signing key, symlinks, macOS defaults, toolchains, agents, VS Code |

The first account on a machine runs both. Later accounts run `user` steps in full and
`system` steps in verify-only mode. Most state is already per-account by nature —
`defaults write` targets `~/Library/Preferences`, `fnm` and `pyenv` live under `~`.
Each account keeps its own clone of this repo, so accounts can sit on different commits.

**Homebrew is the one shared mutable resource.** `/opt/homebrew` is owned by whoever
installs it; a second account can run every binary but cannot `brew install`. On a
second account, setup detects this and offers an explicit opt-in:

```sh
sudo chgrp -R admin /opt/homebrew && sudo chmod -R g+w /opt/homebrew
```

**Documented tradeoff:** any admin user can then write executables that another admin
later runs. Acceptable between trusted users on a shared Mac; the prompt states it
plainly and never applies it silently. Declining leaves the account read-only against
the shared prefix, with missing formulae reported rather than installed.

### Overlay repos

`HV_OVERLAY` points at a separate repo applied *after* the base, with a fixed contract:

```
overlay/
├── brew/*.Brewfile      # appended to the bundle
├── zshrc.d/*.zsh        # linked into ~/.zshrc.d, sourced after base
├── git/config           # [include]d after base gitconfig, so it wins
├── macos.sh             # run after base defaults
└── steps/*.sh           # optional extra converge steps
```

This keeps employer-specific configuration — corporate CA cert paths, internal npm
registries, GHE credential helpers — in a repo owned by that employer, never in the
Hidden Vector repo, while still being version-controlled and synced across machines.

Consequently `HV_RESTRICTED` stays narrow: it means only "do not shell out to
`code --install-extension`", which corporate SSL inspection breaks. Everything else
corp-specific belongs in the overlay.

---

## The `hv` command

Single entrypoint, symlinked from `bin/hv` to `~/.local/bin/hv`, which is already on `PATH`.

| Command | Behavior |
|---|---|
| `hv setup` | converge this machine to the declared state |
| `hv check` | report drift, mutate nothing, exit nonzero if drifted |
| `hv update` | `git pull` then converge |
| `hv identity` | re-run the identity step |
| `hv machine` | re-run machine name / module selection |

Global flags: `--dry-run`, `--only <step>`, `--yes` (accept all defaults).

### Step sequence

Ordered so that Touch ID is enabled before anything else needs `sudo`. The password is
typed exactly once per machine.

| # | Step | Scope | sudo |
|---|---|---|---|
| 00 | preflight — macOS version, arch, admin rights, Command Line Tools | system | — |
| 05 | Touch ID for sudo (`/etc/pam.d/sudo_local`) | system | once, by password |
| 10 | machine — name, modules, restricted, overlay | system + user | Touch ID |
| 20 | Homebrew install + `core.Brewfile` | system | Touch ID |
| 30 | `gh auth login` → identity → signing key | user | — |
| 40 | symlinks | user | — |
| 50 | module + local + overlay Brewfiles, VS Code extensions | user | Touch ID |
| 60 | macOS defaults | user | — |
| 70 | toolchains — fnm/Node, pyenv/uv | user | — |
| 80 | agent config | user | — |
| 90 | `hv check` | both | — |

Each step is an independently runnable, idempotent script under `setup/steps/`.

**Touch ID caveats, surfaced by the tool rather than buried in docs:**

- A Mac Studio has no built-in sensor. The PAM config is inert without a Magic
  Keyboard with Touch ID. Setup detects this and says so rather than silently
  "succeeding".
- MDM may block writing `/etc/pam.d/sudo_local`, or revert it on the next check-in.
  Setup degrades to password auth and `hv check` reports which world you are in.
- Does not work over SSH. `tmux` needs `pam_reattach`, documented not installed.

### Machine naming

Machines get proper names — Greek myth by convention — because the name is the
per-machine identifier and shows up in the prompt. Step 10 reads the current
`ComputerName`; if it is still a default like `Marks-MacBook-Pro`, it prompts with
suggestions and sets `ComputerName`, `HostName` and `LocalHostName` via `scutil`.
Already-named machines are left alone. Overridable with `--machine-name`, skippable,
and gracefully skipped when MDM blocks `scutil`.

### Modules

`core` is always installed. The rest are opt-in per account.

| Module | Contents | Serves |
|---|---|---|
| `core` | git, delta, gh, starship, zsh plugins, fzf, ripgrep, bat, eza, zoxide | everything |
| `swift` | xcbeautify, Xcode tooling | recipes |
| `web` | fnm, pnpm, vercel, wrangler, supabase, railway | the-house, mkw-data-api, hiddenvector.studio |
| `python` | pyenv, uv | the-house backend |
| `security` | gitleaks, pre-commit | the-house |
| `apps` | VS Code, GitHub Desktop, DB Browser for SQLite | optional |

`security` and the Supabase CLI are new — the current Brewfile is missing tooling that
`the-house` already requires.

### Commit signing

One signing key per account per machine, generated locally and uploaded via
`gh ssh-key add --type signing`. Private keys never move between machines. The
`allowed-signers` file is assembled from a tracked `git/allowed-signers.hv` containing
the team's public signing keys — public information, safe to commit — concatenated
with the local user's own keys.

---

## Agent rails

Given that the first new user is an experienced EM learning to code agentically, this
is the highest-leverage part of the repo and the part that does not exist anywhere yet.
The explicit goal is to bias both the person and their agents toward taking time over
rushing to a goal.

Ships:

- `~/.claude/CLAUDE.md` — house rules, composed via `@import` so an existing personal
  CLAUDE.md survives untouched.
- `~/.claude/settings.json` — shared defaults.
- Plugins — `superpowers`, already in use in `the-house`. Its brainstorming,
  test-driven-development and verification-before-completion gates are precisely the
  rails wanted: design before code, tests before implementation, evidence before
  claiming success.
- `docs/AGENTS.md` — a house convention distilled from the good material already in
  `recipes/AGENTS.md` and `the-house/CLAUDE.md`: issues drive work, small shippable
  units, explicit tradeoffs, human control over automation.

---

## Repository layout

```
dotfiles/
├── README.md
├── bootstrap                      # curl-able first-run entrypoint
├── bin/hv
├── docs/
│   ├── ONBOARDING.md              # org access, gh auth, signing keys, service accounts
│   ├── USAGE.md                   # tools and aliases reference
│   └── AGENTS.md
├── setup/
│   ├── lib/{log,link,prompt,machine,brew}.sh
│   └── steps/{00-preflight,05-touchid,10-machine,20-homebrew,30-identity,
│              40-symlinks,50-packages,60-macos,70-toolchains,80-agents,90-check}.sh
├── brew/{core,swift,web,python,security,apps}.Brewfile
├── git/{gitconfig,gitignore_global,allowed-signers.hv}
├── zsh/{.zprofile,.zshrc,.zshrc.d/*.zsh}
├── config/starship.toml
└── claude/{CLAUDE.md,settings.json}
```

## Bootstrap

The repo is **public**, which allows a single-command first run:

```sh
curl -fsSL https://hiddenvector.studio/dotfiles | bash
```

`bootstrap` stays deliberately thin: it installs the Command Line Tools (needed for
`git` to exist at all), clones the repo to
`~/Developer/github.com/hiddenvector/dotfiles`, and `exec`s `hv setup`. It does not
duplicate any converge step — `hv setup` owns the full sequence including Touch ID (05)
and Homebrew (20), so a first run and a repair run take the identical code path.
Nothing sensitive lives in the repo by design — identity, secrets and
corporate configuration are all outside it — so there is nothing to protect by making
it private, and a private repo would add four manual steps to every fresh machine.

Users who prefer not to pipe curl into bash can download, read, then run; the README
documents both.

## First-run interaction model

First run is a conversation: prompts with sensible defaults, where identity defaults
are read from `gh api user` after authentication. Every answer is persisted, so
re-runs are silent. Flags exist as overrides for people who already know what they
want. This favors the first-timer over the expert, deliberately.

## Migration

`hyperspacemark/dotfiles` is **archived, not deleted**, with a README pointer to the
new repo. The new repo starts fresh with a single well-crafted initial commit rather
than inheriting nineteen commits of profile-flag churn that this architecture removes.
History stays linkable in the archived repo.

Personal-only packages currently in the tracked Brewfile — `cask "chatgpt"`,
`cask "codex"` — move to `~/.config/hv/local.Brewfile`.

## Verification

- `hv check` passes on a converged machine and exits nonzero on a drifted one.
- `hv setup` run twice in a row produces no changes on the second run.
- `hv setup --dry-run` mutates nothing.
- Each step is independently re-runnable via `--only`.
- Manual validation across the three real machines: personal laptop, Mac Studio
  (no built-in Touch ID sensor), managed corporate laptop (MDM restrictions, overlay
  repo), plus a second macOS account on a shared Mac.
