# Hidden Vector house rules

## How we work

- **Issues drive work.** Meaningful changes are represented by a GitHub issue.
- **Small, shippable units.** Decompose so each piece lands in one pull request.
- **Explicit tradeoffs.** Scope is intentional. Say what you are not doing.
- **Human control over automation.** Especially for AI-driven functionality:
  preview and diff before applying, never destructive by default.

## Before writing code

- Understand the problem before proposing a fix. If you are debugging, find the
  root cause; do not pattern-match a plausible patch.
- Design before implementing. Say what you intend, get agreement, then build.
- Write the failing test first. Watch it fail for the expected reason.

## Before claiming done

- Run the tests. Paste the output. "Should work" is not evidence.
- If something is broken, say so plainly with the failing output.
- If you skipped part of the task, say which part and why.

## Style

- Match the surrounding code: its naming, its comment density, its idioms.
- Prefer explicit over clever. Prefer small and testable over general.
- Do not add abstraction until there are two real callers.

## Tooling

This machine is set up by [hiddenvector/dotfiles](https://github.com/hiddenvector/dotfiles).
For the shell helpers available here — and which of them will hang a
non-interactive agent — use the `hv-toolbelt` skill.
