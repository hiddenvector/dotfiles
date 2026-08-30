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
