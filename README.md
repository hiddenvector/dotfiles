# hiddenvector/dotfiles

A convergent macOS environment installer for Hidden Vector. One command
takes a fresh Apple Silicon Mac — or one that's drifted from what this repo
declares — to the same known state: shell, git, Homebrew packages, macOS
defaults, SSH signing identity, and whatever language toolchains this
person's machine has opted into.

"Convergent" is the operative word: there is no separate "first install"
script and "fix things later" script. `hv setup` is both. Run it on day one
and it builds the machine from nothing; run it again next month and it only
touches what has drifted, reporting everything else as already converged.

## Install

```bash
curl -fsSL https://hiddenvector.studio/dotfiles | bash
```

Piping a script into `bash` sight unseen means trusting it without reading
it first. If you'd rather read it first, download it, look it over, then
run it yourself:

```bash
curl -fsSL https://hiddenvector.studio/dotfiles -o /tmp/hv-bootstrap && less /tmp/hv-bootstrap && bash /tmp/hv-bootstrap
```

Either way, `bootstrap` does the minimum needed to hand off to the repo
itself: install Command Line Tools if missing, clone (or `pull` if the
clone already exists) to `~/Developer/github.com/hiddenvector/dotfiles`,
then `exec bin/hv setup`. Every actual converge step — packages, macOS
defaults, symlinks, identity, and so on — lives in `hv setup`, not in
`bootstrap`, so re-running `bootstrap` on an already-set-up machine takes
the identical path as running it the first time.

## The `hv` command

Everything after the initial clone goes through `bin/hv`:

| Command | What it does |
|---|---|
| `hv setup` | Converge this machine to the declared state. Safe to re-run any time — an already-converged step is skipped. |
| `hv check` | Report drift without changing anything. Exits 1 if the machine has drifted from what the repo (and this person's config) declare. |
| `hv update` | `git pull --ff-only` this repo, then `hv setup`. |
| `hv identity` | Re-run just the identity step (SSH signing key, `gh auth login`). |
| `hv machine` | Re-run just the machine-name and module-selection step. |
| `hv overlay init` | Create and wire up a personal overlay repo (`hv overlay` alone is equivalent). |
| `hv cheatsheet [module\|--all\|--regenerate]` | Print usage docs. With no argument, only the modules enabled here; `--all`, every module; a module name, just that module's fragment (even if it isn't enabled); `--regenerate` rewrites `docs/USAGE.md` instead of printing. An unknown module name exits nonzero rather than printing nothing. |

Flags accepted by the convergence commands: `--only <step-name>` (run a
single step), `--dry-run` (preview what would change, change nothing),
`--yes` (accept defaults without prompting).

Running `hv` with no arguments, or an unrecognized command, prints usage to
stderr and exits nonzero.

## Three layers

Nothing this tool touches is stored in more than one place, and each layer
has one job:

1. **The tracked repo** (this one). Everything that's the same for every
   Hidden Vector machine: shell config, git config, Homebrew package lists
   per module, macOS defaults, setup steps. Changes here land for everyone
   the next time they `hv update`.
2. **Per-user config**, at `~/.config/hv/config`. The handful of choices
   that differ per person, not per machine: which modules are enabled
   (`HV_MODULES`), whether an overlay is configured (`HV_OVERLAY`), and
   similar preferences. Read by `hv::config_load` at the start of every
   `hv` invocation.
3. **Machine facts**, derived live, never stored. Things like the current
   Mac's `ComputerName`, whether it's MDM-managed, whether it has a Touch
   ID sensor, or its CPU architecture are asked of the OS fresh every time
   (`setup/lib/machine.sh`) rather than cached to a file. A Mac wiped and
   reinstalled, or a second account on the same Mac, never has to worry
   about a stale cached fact disagreeing with reality.

## Modules

A module is a named bundle of extra tooling beyond the always-installed
`core` (shell, prompt, git, and `hv` itself). The current set:

- `swift` — Xcode and Swift-package tooling (`xcbeautify`, `swiftlint`).
- `web` — Node and web-deployment tooling (`fnm`, `pnpm`, `vercel`,
  `supabase`, `railway`, `jq`).
- `python` — Python tooling (`pyenv`, `uv`).
- `security` — secret-scanning and git-hook tooling (`gitleaks`,
  `pre-commit`).
- `apps` — everyday GUI applications.

Which modules are enabled lives in `~/.config/hv/config` as `HV_MODULES`
(`core` is mandatory and always included); `hv machine` is what prompts for
this. Each module owns a `brew/<module>.Brewfile` that `hv setup` installs
with `brew bundle`, and a `docs/usage/<module>.md` fragment that both
`docs/USAGE.md` and `hv cheatsheet` are generated from — so the reference
doc, the printed cheatsheet, and the installed-module cheatsheet can never
say three different things.

## Overlays

An overlay is a person's own layer on top of this shared base — packages
only they want, aliases only they use, git settings only they need —
tracked in their own repo instead of living as untracked, unsynced files on
one machine. `hv overlay init` walks through adopting or creating one; once
configured (`HV_OVERLAY` in the per-user config), `hv setup` picks up the
overlay's `brew/*.Brewfile`, `zshrc.d/*.zsh`, `git/config`, `macos.sh`, and
`steps/*.sh` automatically, applying the overlay's version last so it wins
over the shared defaults.

## Where to go next

[`docs/START-HERE.md`](docs/START-HERE.md) is the short version: ten
commands worth knowing on day one. [`docs/USAGE.md`](docs/USAGE.md) is the
full reference, generated from `docs/usage/*.md`, one file per module.
[`docs/ONBOARDING.md`](docs/ONBOARDING.md) covers what `hv setup` cannot do
for you — account access, and getting each client repo running locally.
