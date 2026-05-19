# start-cc-5h-window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Overview

Build `start-cc-5h-window` as an installable macOS shell utility that schedules a minimal Claude Code headless prompt. The implementation must default to `07:00` in `Australia/Melbourne`, use app-prefixed config names, support dry-run before scheduler mutation, and avoid overwriting unrelated `pmset` schedules.

## File Structure

- Create `bin/start-cc-5h-window`
  - Executable POSIX-style shell script.
  - Owns command dispatch, config loading, validation, logging, dry-run behavior, plist rendering, `launchctl`, `pmset`, and Claude invocation.
- Create `share/com.local.start-cc-5h-window.plist.template`
  - `launchd` template with placeholders for executable path, hour, minute, stdout log path, and stderr log path.
- Create `test/start-cc-5h-window-test.sh`
  - Shell test runner for pure helper behavior and dry-run output.
  - Uses temporary HOME directories and command stubs so tests do not mutate real `launchd`, `pmset`, or Claude state.
- Create `test/fixtures/`
  - Optional fixture directory for expected plist output if inline assertions become hard to read.
- Create `README.md`
  - Installation, configuration, dry-run, manual run, status, uninstall, and macOS scheduler caveats.

## Task 1: Test Harness and Script Skeleton

- Create: `bin/start-cc-5h-window`
- Create: `test/start-cc-5h-window-test.sh`

- [ ] **Step 1: Write the failing smoke test**

  Add `test/start-cc-5h-window-test.sh`:

  ```sh
  #!/bin/sh
  set -eu

  ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
  APP="$ROOT_DIR/bin/start-cc-5h-window"

  fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
  }

  assert_contains() {
    haystack=$1
    needle=$2
    message=$3
    printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null || fail "$message"
  }

  output=$("$APP" help)
  assert_contains "$output" "start-cc-5h-window install" "help lists install"
  assert_contains "$output" "start-cc-5h-window run" "help lists run"

  printf 'ok - smoke\n'
  ```

- [ ] **Step 2: Run the test to verify it fails**

  Run:

  ```sh
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: fails because `bin/start-cc-5h-window` does not exist.

- [ ] **Step 3: Implement the minimal executable skeleton**

  Add `bin/start-cc-5h-window`:

  ```sh
  #!/bin/sh
  set -eu

  APP_NAME=start-cc-5h-window

  usage() {
    cat <<'USAGE'
  start-cc-5h-window install [--dry-run] [--overwrite-pmset]
  start-cc-5h-window uninstall [--dry-run]
  start-cc-5h-window status
  start-cc-5h-window run
  start-cc-5h-window configure
  start-cc-5h-window help
  USAGE
  }

  main() {
    command=${1:-help}
    case "$command" in
      help|-h|--help) usage ;;
      *) printf '%s: unknown command: %s\n' "$APP_NAME" "$command" >&2; usage >&2; exit 2 ;;
    esac
  }

  main "$@"
  ```

  Mark it executable:

  ```sh
  chmod +x bin/start-cc-5h-window
  ```

- [ ] **Step 4: Run the test and syntax check**

  Run:

  ```sh
  sh -n bin/start-cc-5h-window
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: syntax check passes and test prints `ok - smoke`.

- [ ] **Step 5: Commit**

  Run:

  ```sh
  git status --short
  git diff
  git add bin/start-cc-5h-window test/start-cc-5h-window-test.sh
  git diff --cached
  git commit -m "test: add shell harness"
  ```

## Task 2: Config Defaults and Validation

- Modify: `bin/start-cc-5h-window`
- Modify: `test/start-cc-5h-window-test.sh`

- [ ] **Step 1: Add failing tests for default config and validation**

  Extend `test/start-cc-5h-window-test.sh` with isolated HOME setup:

  ```sh
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  HOME="$tmpdir/home"
  mkdir -p "$HOME"
  export HOME

  output=$("$APP" status)
  assert_contains "$output" "START_CC_5H_WINDOW_TIME=07:00" "status shows default time"
  assert_contains "$output" "START_CC_5H_WINDOW_TIMEZONE=Australia/Melbourne" "status shows default timezone"
  assert_contains "$output" "START_CC_5H_WINDOW_PROMPT=Reply with: ok" "status shows default prompt"
  ```

- [ ] **Step 2: Run the test to verify it fails**

  Run:

  ```sh
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: fails because `status` is not implemented.

- [ ] **Step 3: Implement config path, defaults, loading, and validation**

  Add helpers to `bin/start-cc-5h-window`:

  ```sh
  config_dir() { printf '%s/.config/%s\n' "$HOME" "$APP_NAME"; }
  config_file() { printf '%s/config.env\n' "$(config_dir)"; }
  log_dir() { printf '%s/Library/Logs/%s\n' "$HOME" "$APP_NAME"; }
  launch_agent_file() { printf '%s/Library/LaunchAgents/com.local.%s.plist\n' "$HOME" "$APP_NAME"; }

  set_defaults() {
    START_CC_5H_WINDOW_TIME=${START_CC_5H_WINDOW_TIME:-07:00}
    START_CC_5H_WINDOW_TIMEZONE=${START_CC_5H_WINDOW_TIMEZONE:-Australia/Melbourne}
    START_CC_5H_WINDOW_PROMPT=${START_CC_5H_WINDOW_PROMPT:-Reply with: ok}
    START_CC_5H_WINDOW_CLAUDE_BIN=${START_CC_5H_WINDOW_CLAUDE_BIN:-claude}
  }

  load_config() {
    set_defaults
    file=$(config_file)
    if [ -f "$file" ]; then
      # shellcheck disable=SC1090
      . "$file"
      set_defaults
    fi
  }

  validate_time() {
    case "$1" in
      [0-2][0-9]:[0-5][0-9])
        hour=${1%:*}
        [ "$hour" -le 23 ] || return 1
        ;;
      *) return 1 ;;
    esac
  }

  validate_config() {
    validate_time "$START_CC_5H_WINDOW_TIME" || {
      printf '%s: invalid START_CC_5H_WINDOW_TIME: %s\n' "$APP_NAME" "$START_CC_5H_WINDOW_TIME" >&2
      return 1
    }
    [ -n "$START_CC_5H_WINDOW_TIMEZONE" ] || return 1
    [ -n "$START_CC_5H_WINDOW_PROMPT" ] || return 1
    [ -n "$START_CC_5H_WINDOW_CLAUDE_BIN" ] || return 1
  }
  ```

  Add `status` dispatch that loads config, validates it, and prints effective values plus file paths.

- [ ] **Step 4: Run tests**

  Run:

  ```sh
  sh -n bin/start-cc-5h-window
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: all tests pass.

- [ ] **Step 5: Commit**

  Run:

  ```sh
  git status --short
  git diff
  git add bin/start-cc-5h-window test/start-cc-5h-window-test.sh
  git diff --cached
  git commit -m "feat: add config validation"
  ```

## Task 3: Plist Rendering and Dry-Run Install

- Create: `share/com.local.start-cc-5h-window.plist.template`
- Modify: `bin/start-cc-5h-window`
- Modify: `test/start-cc-5h-window-test.sh`

- [ ] **Step 1: Add failing tests for dry-run install**

  Add assertions that:

  - `install --dry-run` prints the config file path.
  - `install --dry-run` prints `launchctl bootstrap gui/`.
  - `install --dry-run` prints `pmset repeat wakeorpoweron`.
  - It includes hour `7` and minute `0` in the rendered plist output.

- [ ] **Step 2: Run the test to verify it fails**

  Run:

  ```sh
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: fails because `install` is not implemented.

- [ ] **Step 3: Add plist template**

  Create `share/com.local.start-cc-5h-window.plist.template` with placeholders:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.local.start-cc-5h-window</string>
    <key>ProgramArguments</key>
    <array>
      <string>__APP_PATH__</string>
      <string>run</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
      <key>Hour</key>
      <integer>__HOUR__</integer>
      <key>Minute</key>
      <integer>__MINUTE__</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>__STDOUT_LOG__</string>
    <key>StandardErrorPath</key>
    <string>__STDERR_LOG__</string>
  </dict>
  </plist>
  ```

- [ ] **Step 4: Implement dry-run install and rendering**

  Add helpers:

  - `script_path` using `cd "$(dirname "$0")" && pwd`.
  - `template_file` relative to the repository layout.
  - `time_hour` and `time_minute`.
  - `wake_time` that subtracts 5 minutes from configured time.
  - `render_plist` using `sed` placeholder replacement.
  - `print_install_plan` that prints all paths and intended commands.

  Implement `install --dry-run` so it does not create files and does not run `launchctl` or `pmset`.

- [ ] **Step 5: Run tests**

  Run:

  ```sh
  sh -n bin/start-cc-5h-window
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: all tests pass.

- [ ] **Step 6: Commit**

  Run:

  ```sh
  git status --short
  git diff
  git add bin/start-cc-5h-window share/com.local.start-cc-5h-window.plist.template test/start-cc-5h-window-test.sh
  git diff --cached
  git commit -m "feat: add dry-run install"
  ```

## Task 4: Real Install and Conservative pmset Handling

- Modify: `bin/start-cc-5h-window`
- Modify: `test/start-cc-5h-window-test.sh`

- [ ] **Step 1: Add failing tests using command stubs**

  In the test script:

  - Create a temporary `stubs/` directory.
  - Add executable stub scripts for `launchctl` and `pmset` that append arguments to files under `$tmpdir/calls`.
  - Prepend `stubs/` to `PATH`.
  - Run `"$APP" install`.
  - Assert config, plist, and log directories are created under the temporary HOME.
  - Assert the stubbed `launchctl` command was called.
  - Assert the stubbed `pmset` command was called when `pmset -g sched` returns no repeat wake schedule.

- [ ] **Step 2: Run the test to verify it fails**

  Run:

  ```sh
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: fails because real install behavior is not implemented.

- [ ] **Step 3: Implement file writes and launchctl loading**

  Implement `install` without `--dry-run`:

  - `mkdir -p` config, launch agent, and log directories.
  - Write config with defaults only if it does not already exist.
  - Render plist to `~/Library/LaunchAgents/com.local.start-cc-5h-window.plist`.
  - Run `launchctl bootout "gui/$(id -u)" "$plist"` and ignore failure.
  - Run `launchctl bootstrap "gui/$(id -u)" "$plist"`.
  - Run `launchctl enable "gui/$(id -u)/com.local.start-cc-5h-window"`.

- [ ] **Step 4: Implement conservative pmset handling**

  Add:

  - `pmset_schedule` that runs `pmset -g sched`.
  - `has_repeat_wake_schedule` that detects an existing repeat wake schedule.
  - `apply_pmset_schedule` that runs `pmset repeat wakeorpoweron MTWRFSU "$wake_time"` only when no conflicting repeat wake schedule exists, unless `--overwrite-pmset` is present.

  If a conflict exists without overwrite, print the existing schedule and return success with a warning. Do not mutate `pmset`.

- [ ] **Step 5: Run tests**

  Run:

  ```sh
  sh -n bin/start-cc-5h-window
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: all tests pass.

- [ ] **Step 6: Commit**

  Run:

  ```sh
  git status --short
  git diff
  git add bin/start-cc-5h-window test/start-cc-5h-window-test.sh
  git diff --cached
  git commit -m "feat: add installer"
  ```

## Task 5: Run Command and Logging

- Modify: `bin/start-cc-5h-window`
- Modify: `test/start-cc-5h-window-test.sh`

- [ ] **Step 1: Add failing tests for `run`**

  Add a `claude` stub that prints `ok` and records arguments.

  Assert:

  - `run` calls `claude --bare -p "Reply with: ok"`.
  - `run` creates a log file under `~/Library/Logs/start-cc-5h-window/`.
  - log content includes `status=success` and `exit_code=0`.

- [ ] **Step 2: Run the test to verify it fails**

  Run:

  ```sh
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: fails because `run` is not implemented.

- [ ] **Step 3: Implement timezone warning and Claude invocation**

  Add:

  - `current_timezone` using `systemsetup -gettimezone` when available, with a fallback to `date +%Z`.
  - `warn_timezone_mismatch` that logs but does not abort.
  - `run_claude_ping` that invokes `"$START_CC_5H_WINDOW_CLAUDE_BIN" --bare -p "$START_CC_5H_WINDOW_PROMPT"` and captures stdout, stderr, and exit code.

- [ ] **Step 4: Implement durable run logs**

  Log to a timestamped file such as:

  ```text
  ~/Library/Logs/start-cc-5h-window/run-YYYYMMDD-HHMMSS.log
  ```

  Include:

  - start timestamp
  - configured time and timezone
  - command path
  - stdout
  - stderr
  - exit code
  - `status=success` or `status=failure`

  Return Claude's exit code from `run`.

- [ ] **Step 5: Run tests**

  Run:

  ```sh
  sh -n bin/start-cc-5h-window
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: all tests pass.

- [ ] **Step 6: Commit**

  Run:

  ```sh
  git status --short
  git diff
  git add bin/start-cc-5h-window test/start-cc-5h-window-test.sh
  git diff --cached
  git commit -m "feat: add claude ping"
  ```

## Task 6: Status, Configure, and Uninstall

- Modify: `bin/start-cc-5h-window`
- Modify: `test/start-cc-5h-window-test.sh`

- [ ] **Step 1: Add failing tests for remaining commands**

  Assert:

  - `status` prints config, plist path, log dir, launch agent loaded state, pmset schedule summary, and latest log path when present.
  - `configure` creates or updates `config.env` using environment overrides.
  - `uninstall --dry-run` prints intended `launchctl bootout` and plist removal.
  - `uninstall` removes the plist and calls `launchctl bootout`.
  - `uninstall` does not remove an unrelated `pmset` schedule.

- [ ] **Step 2: Run the test to verify it fails**

  Run:

  ```sh
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: fails on missing or incomplete commands.

- [ ] **Step 3: Implement `configure`**

  `configure` should:

  - create config directory
  - preserve existing values unless corresponding environment variables are set
  - write a complete `config.env`
  - validate the resulting config

- [ ] **Step 4: Implement `status` details**

  `status` should:

  - print effective config
  - print config path, plist path, and log directory
  - run `launchctl print "gui/$(id -u)/com.local.start-cc-5h-window"` and summarize loaded/not loaded
  - run `pmset -g sched` and print the relevant schedule block
  - show the newest `run-*.log` when present

- [ ] **Step 5: Implement `uninstall`**

  `uninstall` should:

  - support `--dry-run`
  - run `launchctl bootout "gui/$(id -u)" "$plist"` and ignore missing-agent failures
  - remove the plist
  - inspect `pmset -g sched`
  - only clear the repeat wake schedule when it matches the app's expected wake time, otherwise warn and leave it alone

- [ ] **Step 6: Run tests**

  Run:

  ```sh
  sh -n bin/start-cc-5h-window
  sh test/start-cc-5h-window-test.sh
  ```

  Expected: all tests pass.

- [ ] **Step 7: Commit**

  Run:

  ```sh
  git status --short
  git diff
  git add bin/start-cc-5h-window test/start-cc-5h-window-test.sh
  git diff --cached
  git commit -m "feat: add management commands"
  ```

## Task 7: Documentation and Final Verification

- Create: `README.md`
- Modify: `docs/superpowers/specs/2026-05-19-start-cc-5h-window-design.md` only if implementation details force a documented correction.

- [ ] **Step 1: Write README**

  Include:

  - purpose and quota caveat: the app is intended to start the 5-hour window, not guarantee Anthropic quota semantics
  - install command
  - dry-run first workflow
  - default config
  - how to customize time and timezone
  - how to test `run`
  - status and uninstall commands
  - note that `pmset repeat` is system-wide and handled conservatively

- [ ] **Step 2: Run full verification**

  Run:

  ```sh
  sh -n bin/start-cc-5h-window
  sh test/start-cc-5h-window-test.sh
  START_CC_5H_WINDOW_TIME=07:00 START_CC_5H_WINDOW_TIMEZONE=Australia/Melbourne bin/start-cc-5h-window install --dry-run
  ```

  Expected:

  - syntax check passes
  - test runner passes
  - dry-run prints config path, plist path, launchctl command, and pmset command without mutating scheduler state

- [ ] **Step 3: Inspect diffs**

  Run:

  ```sh
  git status --short
  git diff
  ```

  Confirm only expected docs/code/test files changed.

- [ ] **Step 4: Commit**

  Run:

  ```sh
  git add README.md
  git diff --cached
  git commit -m "docs: add usage guide"
  ```

## Final Review

- [ ] Run `git log --oneline --decorate -10` and verify commits are small and conventional.
- [ ] Run `git status --short` and verify the worktree is clean.
- [ ] Run a code review before finalizing non-trivial implementation changes.
