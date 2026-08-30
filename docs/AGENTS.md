# Working with agents

The house convention for using AI coding agents (Claude Code and similar) on
Hidden Vector repos.

## 1. What agents are for here

Agents draft and verify. Humans decide.

An agent can write a first pass at a fix, run the test suite, read the
diff back, and tell you what it found. What it should not do on its own is
decide that a piece of work is done, merge it, push to a protected branch,
or take an action with real-world side effects (deleting data, creating a
GitHub repo, sending something) without a human looking at the result
first. Treat an agent's "done" the same way you'd treat a junior
engineer's: a claim to be checked, not a fact to be trusted.

## 2. Before code

For anything beyond a trivial fix, work in this order — don't let an agent
skip a step because it's confident:

1. **Brainstorm** (`superpowers:brainstorming`) — explore intent and
   requirements before committing to an approach. This is where you catch
   "that's not actually what I wanted" cheaply.
2. **Plan** (`superpowers:writing-plans`) — turn the agreed approach into a
   written, step-by-step plan before touching code. A plan you can read is
   a plan you can disagree with before it's built.
3. **Test-first** (`superpowers:test-driven-development`) — write the
   failing test, watch it fail for the expected reason, then write the
   code that makes it pass. An agent that writes the implementation before
   the test has no way to prove the test would have caught the bug it's
   fixing.

When something breaks and the cause isn't obvious, reach for
`superpowers:systematic-debugging` instead of letting the agent
pattern-match a plausible-looking patch onto the symptom.

## 3. Per-repo context

Every client repo carries its own agent instructions — read them before
touching that repo; they take precedence over generic house habits.

| Repo | Instruction file |
|---|---|
| `the-house` | `CLAUDE.md` |
| `recipes` | `AGENTS.md` |
| `mkw-data-api` | none yet — default to this document and ask before assuming a convention |
| `hiddenvector.studio` | none yet — default to this document and ask before assuming a convention |

## 4. Reviewing agent output

What agents on this project have actually gotten wrong, not a generic
checklist:

- **Unrun tests.** A test file was written and never executed — or was
  executed but the failure was silently swallowed. This project shipped a
  test suite where a non-final `[[ ]]` assertion couldn't fail the test at
  all under `set -e` on bash 3.2 (a negated `! cmd` in non-final position
  has the same problem, in every bash). "The tests pass" is only true if
  you can see the run and the assertions in it actually execute.
- **Silent scope changes.** An installer step reported success for work it
  never did — it exited 0 without having performed the action it claimed.
  Read the diff, not just the exit code and the agent's summary of it.
- **Invented APIs and unauthorized side effects.** Calling a function,
  flag, or CLI subcommand that doesn't exist, or — worse — one that does
  exist and does something real: this project caught an agent that would
  have run an ungated `gh repo create` and a test that destroyed
  uncommitted work in the working tree it was run in. Anything
  irreversible (deleting, force-pushing, creating external resources)
  needs a human's explicit go-ahead in the moment, not a plan that
  mentioned it once.

Verify by running the commands yourself and reading the actual output, the
same way `superpowers:verification-before-completion` insists on — not by
trusting the agent's account of what happened.

## 5. When to stop an agent

Stop and take over (or restart with more context) when you see:

- **Repeated failed fixes.** The same test keeps failing after two or three
  attempted patches — the agent is pattern-matching, not diagnosing.
- **A growing diff.** The changeset keeps expanding to touch more files
  than the task justifies. That's usually scope creep or a wrong root
  cause, not progress.
- **Confident claims without output.** "This should work now" or "that's
  fixed" with no test run, no command output, no diff shown. Ask to see
  the evidence; if there isn't any, the claim isn't done.
