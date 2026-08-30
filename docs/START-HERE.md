# Start here

Ten commands worth knowing on day one. Everything else — the full behavior
of each, plus every module this machine can enable — lives in
[`USAGE.md`](USAGE.md).

| Command | Reach for it when... |
|---|---|
| `hv check` | you want to know if this machine has drifted from what the repo declares, without changing anything. |
| `hv cheatsheet` | you forget what a command does; prints usage docs for whatever's installed here. |
| `g` | you'd type `git status` or any other `git` subcommand — `g` is a shorter alias for both. |
| `ff` | you know roughly what file you want and would rather fuzzy-pick it than type the path (needs a terminal, not a script). |
| `fif` | you're hunting for a string across the whole tree and want a fuzzy-searchable result list. |
| `j` | you want to jump into a project under `~/Developer` by a fragment of its name. |
| `z` | you want to jump to a directory you've `cd`'d into recently, by frecency. |
| `ll` | you want a long file listing that also shows each file's git status. |
| `gbc` | you're starting new work and want the branch created and pushed upstream in one step. |
| `gprune` | you want to clean up local branches whose remote counterpart is already gone. |

See [`USAGE.md`](USAGE.md) for the complete reference, including every
interactive command's exact behavior and the modules (Swift, Web, Python,
Security) you can enable beyond this core set.
