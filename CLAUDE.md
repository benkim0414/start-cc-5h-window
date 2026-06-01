# start-cc-5h-window

A macOS command-line tool (`bin/start-cc-5h-window`, POSIX `/bin/sh`) that installs a
launchd LaunchAgent plus a `pmset` wake schedule to fire a small `claude` ping at a
configured local time, anchoring the start of the 5-hour usage window. Tested via a
stub-based shell harness (`test/start-cc-5h-window-test.sh`, run with `sh`).

## Documented Solutions

`docs/solutions/` — documented solutions to past problems (bugs, best practices,
workflow patterns), organized by category with YAML frontmatter (`module`, `tags`,
`problem_type`, `component`). Relevant when implementing or debugging in documented
areas — e.g. the launchd/pmset scheduler, the timeout watchdog, or config parsing.

## Conventions

- **Commits:** Conventional Commits (`type(scope): description`); this repo's history is
  unscoped (`fix:`, `feat:`, `docs:`, `chore:`, `refactor:`, `test:`). One logical change
  per commit.
- **Shell:** the CLI targets POSIX `/bin/sh` with `set -eu`. `set -o pipefail` is
  unavailable in `/bin/sh` and must not be added. Keep `shellcheck` clean.
