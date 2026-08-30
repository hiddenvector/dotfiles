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
