---
title: POSIX /bin/sh timeout watchdog hangs callers by holding the command-substitution pipe
date: 2026-06-01
category: docs/solutions/logic-errors/
module: start-cc-5h-window
problem_type: logic_error
component: tooling
symptoms:
  - "Test suite passes once then hangs ~120s on the next run, with no assertion failure"
  - "output=$(\"$APP\" run) stalls even though the claude command already exited 0"
  - "Detached sleep processes linger after each command-substitution run (one per call)"
root_cause: async_timing
resolution_type: code_fix
severity: high
tags:
  - posix-shell
  - file-descriptors
  - command-substitution
  - background-watchdog
  - timeout
  - macos
  - pkill
---

# POSIX /bin/sh timeout watchdog hangs callers by holding the command-substitution pipe

## Problem

macOS ships no `timeout(1)`, so a per-invocation timeout for the scheduled `claude` ping was implemented with a background-watchdog subshell (`( sleep N; kill "$cmd_pid" ) &`) in `run_claude_ping` (`bin/start-cc-5h-window`). The watchdog subshell — and its `sleep` child — inherited the function's stdout file descriptor, so any caller invoking the command via command substitution (`output=$(... run)`) blocked until the `sleep` expired, hanging for up to the full timeout (default 120s) after the command had logically finished.

## Symptoms

- The shell test suite passed on one run, then hung ~120s on the next, with **no assertion failure and no error output** — a classic intermittent, timing-dependent stall.
- Tests shaped like `output=$("$APP" run)` stalled even though the `claude` stub exited instantly and `run()` had already returned.
- After the watchdog was first redirected to `/dev/null`, detached `sleep` processes lingered (one per command-substitution test, ~8 per suite run) until they expired on their own.

## What Didn't Work

- **Trusting a single green run.** The bug was introduced by a code-review fix and the first suite run passed (the fast stub finished before the watchdog's `sleep`, so the pipe happened to close in time). The hang only appeared on a subsequent run. A single green run is not trustworthy for any path mixing background processes, pipes, and command substitution — re-run at least twice.
- **Redirecting the watchdog's stdio alone.** Adding `</dev/null >/dev/null 2>&1` to the subshell *did* fix the hang (the `sleep` then inherits `/dev/null`, not the pipe), but it left detached `sleep` processes lingering. Killing the watchdog subshell does **not** reap a `sleep` child it already forked — those orphans held nothing (so they caused no further hang) but sat around until the timeout elapsed. The fix needed a second part: explicitly reap the grandchild.

## Solution

Two changes in `run_claude_ping`: redirect the watchdog's descriptors off the caller's pipe, and reap both the watchdog and its `sleep` child.

Before (broken — watchdog inherits the caller's stdout pipe):

```sh
run_claude_ping() {
  stdout_file=$1; stderr_file=$2
  set +e
  "$START_CC_5H_WINDOW_CLAUDE_BIN" --bare -p "$START_CC_5H_WINDOW_PROMPT" >"$stdout_file" 2>"$stderr_file" &
  cmd_pid=$!
  ( sleep "$RUN_TIMEOUT"; kill "$cmd_pid" 2>/dev/null ) &
  watchdog_pid=$!
  wait "$cmd_pid"; exit_code=$?
  kill "$watchdog_pid" 2>/dev/null; wait "$watchdog_pid" 2>/dev/null
  set -e
  return "$exit_code"
}
```

After (fixed):

```sh
run_claude_ping() {
  stdout_file=$1; stderr_file=$2
  set +e
  "$START_CC_5H_WINDOW_CLAUDE_BIN" --bare -p "$START_CC_5H_WINDOW_PROMPT" >"$stdout_file" 2>"$stderr_file" &
  cmd_pid=$!
  # The watchdog and its sleep child must not inherit this function's stdout,
  # or an orphaned sleep would hold the pipe open and stall a caller reading
  # our output via command substitution. Redirect all of its descriptors.
  ( sleep "$RUN_TIMEOUT"; kill "$cmd_pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
  watchdog_pid=$!
  wait "$cmd_pid"; exit_code=$?
  # Reap the watchdog and its sleep child so no detached sleep lingers.
  pkill -P "$watchdog_pid" 2>/dev/null
  kill "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  set -e
  return "$exit_code"
}
```

The timeout test stub uses `exec sleep 30` so the killed PID is the `sleep` itself (no grandchild to orphan), and asserts `status=failure` within a bounded wall-clock.

## Why This Works

Command substitution `output=$(func)` connects `func`'s stdout to a pipe and does **not** return until EOF on the read end — which arrives only when every process holding the pipe's write end has closed it. In the broken version the watchdog subshell and its `sleep` both inherited that write end, so `$()` blocked until the `sleep` exited (up to `RUN_TIMEOUT`), even though `wait "$cmd_pid"` had already returned the real command's status.

Redirecting the subshell with `</dev/null >/dev/null 2>&1` applies to the whole subshell *before* it forks `sleep`, so `sleep` starts with fd 1 pointing at `/dev/null`. Once `run_claude_ping` returns, nothing holds the pipe's write end, EOF arrives, and `$()` returns immediately. `pkill -P "$watchdog_pid"` then SIGTERMs the `sleep` grandchild (which `kill "$watchdog_pid"` would not reach), so no detached process lingers. `pkill` is not POSIX but is present on macOS, the script's only target.

## Prevention

- **A timeout watchdog in `/bin/sh` must isolate its descriptors.** Always launch it as `( sleep "$N"; kill "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &`. If it shares the parent's stdout, any caller using command substitution hangs until the timeout fires.
- **Reap the grandchild.** Killing a watchdog subshell does not reap a `sleep` it already forked. Follow with `pkill -P "$watchdog_pid"` (macOS/BSD) before `kill`/`wait`.
- **Test the function through command substitution, not just a direct call.** The pipe-EOF hang only manifests under `$(...)`; a direct `func; echo $?` never blocks because there is no pipe to keep open.
- **Assert bounded wall-clock in timeout tests** so an infinite hang fails loudly instead of looking like a pass:

  ```sh
  start=$(date +%s)
  "$APP" run >/dev/null 2>&1 || :
  [ "$(( $(date +%s) - start ))" -lt 10 ] || fail "run hung past timeout bound"
  ```

- **Intermittent hang with no failure message ⇒ suspect a background process holding a pipe fd.** Run `ps | grep sleep` (or your watchdog command) right after a stall. Note that `set -o pipefail` is unavailable in `/bin/sh`, so pipeline-stage failures are silent — another reason these bugs hide.
- **Do not trust a single green run** for code that mixes command substitution, background processes, and pipes. Run the suite at least twice consecutively, or assert the process count after the test.

## Related Issues

- Introduced and fixed during code review of `bin/start-cc-5h-window` (commit `94157e7`, "feat: bound the claude ping with a timeout watchdog").
- Design/spec: `docs/superpowers/specs/2026-05-19-start-cc-5h-window-design.md`, plan `docs/superpowers/plans/2026-05-19-start-cc-5h-window.md` (neither anticipated the watchdog fd hazard).
- Same script documents the related POSIX constraint that `set -o pipefail` is unavailable in `/bin/sh` (see the comment near `set -eu`).
