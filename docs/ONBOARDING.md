# Onboarding

This is the checklist for a new person's first day: accounts, access, and
what to do inside each client repo that `hv setup` cannot do for you.

## Accounts and access

1. **GitHub org access.** Ask to be added to the `hiddenvector` GitHub
   organization before you clone anything — every repo below lives there.
2. **`gh auth login`.** Run `hv setup` (or `hv identity` on its own) and it
   will call this for you if you aren't already authenticated; you can also
   run it yourself first. This is also what lets HTTPS git operations
   authenticate without a password prompt — `git/gitconfig` in this repo
   wires `gh auth git-credential` in as the credential helper for
   `github.com` and `gist.github.com`.
3. **SSH signing key.** `hv identity` (part of `hv setup`) generates a
   per-machine SSH signing key (`~/.ssh/id_ed25519_signing_<machine>`) and
   offers to upload it to your GitHub account with `gh ssh-key add
   --type signing`. If you decline, or the upload fails, add it yourself:
   ```bash
   gh ssh-key add ~/.ssh/id_ed25519_signing_<machine>.pub --type signing \
     --title "<machine> (signing)"
   ```
   Every commit and tag in this org is signed (`commit.gpgsign = true`,
   `gpg.format = ssh`); without a registered key your commits won't show as
   verified.
4. **Vercel, Railway, Supabase accounts.** Ask to be invited to the org's
   Vercel team, Railway project, and Supabase project — these are
   third-party services with their own invitations, not something `hv
   setup` can provision. Once invited, `vercel login`, `railway login`, and
   `supabase login` from any client repo that uses them.
5. **The `supabase` CLI needs a one-time Homebrew trust.** It installs from
   Supabase's own tap (`supabase/tap`), not Homebrew core, and Homebrew
   refuses to load a formula from a tap it hasn't been told to trust. When
   `hv setup` hits this during the packages step, it explains that trusting
   a tap lets it run arbitrary code at install time and asks before doing
   anything — say yes and it trusts the tap and retries automatically; say
   no (or run non-interactively) and it leaves the tap untrusted and tells
   you the command to run yourself later:
   ```bash
   brew trust supabase/tap
   ```

## Per-repo setup

`git clone` gets you the code; `hv setup` never runs a client repo's own
setup for you. Do that once per repo, per the repo's own instructions:

### `the-house`

```bash
npm install
pip install pre-commit && pre-commit install
cp backend/.env.example .env.local   # then fill in your values
cd backend && pip install -r requirements.txt
```

- `.nvmrc` pins Node 22 — `fnm`'s `--use-on-cd` hook (already wired into
  `.zshrc`) switches to it automatically when you `cd` into the repo.
- `.pre-commit-config.yaml` runs `gitleaks` on every commit; `pre-commit
  install` activates that hook.
- The `.env.local` at the repo root is read by both the Vite frontend and
  the Python backend — see `backend/.env.example` for the full set of keys
  (Anthropic, Supabase, Sentry, map provider).

### `recipes`

```bash
make help
```

`recipes` is an Xcode workspace with a `Makefile` front end
(`.DEFAULT_GOAL := help`), so `make help` is the entry point — it lists
every task (`format`, `lint`, `build`, `test`, `ci`, ...) with a one-line
description. There's also a `.env.example` to copy to `.env.local` if you
need the API base URL or an OpenAI key for local work; read
`CONFIGURATION.md` for what each variable does.

### `mkw-data-api`

```bash
npm install
npm run dev   # wraps `wrangler dev`
```

A Cloudflare Worker (Hono + `wrangler`). `npm install` pulls in `wrangler`,
`vitest`, and the TypeScript toolchain; `npm run dev` runs `wrangler dev`
for local iteration. There is no `.env.example` or `.pre-commit-config.yaml`
in this repo as of this writing — don't go looking for one.

### `hiddenvector.studio`

Static HTML — an `index.html` and an `assets/` directory, no build step, no
`package.json`. Clone it and open `index.html`, or serve the directory with
any static file server.

## Migrating from an existing dotfiles setup

If you're moving onto `hv setup` from a personal dotfiles repo you already
had wired up, most of the transition is automatic:

- **Existing symlinks get retargeted, not skipped.** If `~/.zshrc`,
  `~/.gitconfig`, or a `~/.zshrc.d/*.zsh` fragment is already a symlink
  (even one pointing at your old repo), `hv setup` simply repoints it at
  this repo's copy. You don't need to remove anything first.
- **`~/.claude/settings.json`, `~/.secrets`, and an existing `~/.claude/CLAUDE.md`
  are left alone.** `hv setup` never overwrites personal files it can't
  safely merge: an existing `settings.json` is untouched (our suggested
  version is dropped alongside it, at `settings.hv.json`, for you to merge
  by hand); `~/.secrets` is only created if it doesn't already exist; and an
  existing `CLAUDE.md` keeps its content, gaining only a single import line
  for the house rules if it doesn't already have one.

Two things that are *not* plain symlinks need their own handling, and `hv
setup` now covers both:

- **`~/.zshrc.d/local.zsh`.** This file is deliberately never a tracked
  symlink — it's meant to hold real, machine-specific config. If it's
  already a symlink into another dotfiles repo, `hv setup` copies its
  current contents into a real file at the same path (so nothing is lost)
  and warns you it did so. If that symlink was already dangling (the other
  repo, or the file, is already gone), it's replaced with the standard
  stub instead, and you're told the same way. Either way, `--dry-run` only
  reports what it would do — the file isn't touched.
- **An existing SSH signing key.** If `~/.ssh/id_ed25519_signing` (without
  a machine suffix) already exists — typically because it's what your old
  gitconfig referenced — `hv setup` notices before generating a new one and
  asks whether to adopt it for this machine instead. Say yes and your
  identity file points at the key you already have, and it's included when
  `allowed-signers` is rebuilt; say no (or run non-interactively) and it
  generates the usual per-machine key as before.

## When something here doesn't match the repo

These steps were verified against each repo's actual files
(`.pre-commit-config.yaml`, `.env.example`, `.nvmrc`, `Makefile`,
`package.json`) at the time this was written. If a repo has since added or
removed one of these, trust the repo over this document and send a fix.
