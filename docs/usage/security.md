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
