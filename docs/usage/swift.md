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
