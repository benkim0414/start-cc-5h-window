# start-cc-5h-window Design

## Purpose

`start-cc-5h-window` is a tiny macOS utility that schedules a minimal Claude Code prompt intended to start the Claude Code 5-hour usage window before the workday begins.

The default target is 7:00am in `Australia/Melbourne`, so two 5-hour windows can better align with a 9:00am-5:00pm workday. The utility prioritizes minimal subscription usage over maximum scheduling reliability.

## Research Summary

Existing work close to this idea includes `agent-maxprime`, which uses shell, `expect`, and `launchd` to send tiny prompts to agent CLIs on a schedule.

Relevant platform behavior:

- Claude Code supports headless non-interactive prompts with `claude -p`, and `--bare` minimizes extra project context loading.
- Claude Code scheduled tasks and cloud routines exist, but they are less suitable for this project because the goal is to minimize subscription consumption.
- macOS `launchd` is the native user-level scheduler for timed local jobs.
- macOS `pmset` can schedule wake events so the machine is awake before the `launchd` job runs.

Primary references:

- https://code.claude.com/docs/en/headless
- https://code.claude.com/docs/en/scheduled-tasks
- https://code.claude.com/docs/en/routines
- https://support.apple.com/en-my/guide/mac-help/-mchl40376151/mac
- https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html
- https://github.com/bunyodrafikov/agent-maxprime

## Recommendation

Build v1 as an installable shell utility with `launchd` and `pmset` integration.

Shell fits the operating-system integration points directly and keeps the implementation easy to inspect.

## Installable App Shape

The app exposes one executable:

```sh
start-cc-5h-window install
start-cc-5h-window uninstall
start-cc-5h-window status
start-cc-5h-window run
start-cc-5h-window configure
```

`install` creates:

```text
~/.config/start-cc-5h-window/config.env
~/Library/LaunchAgents/com.local.start-cc-5h-window.plist
~/Library/Logs/start-cc-5h-window/
```

It also configures a macOS wake schedule with `pmset` when safe to do so.

`run` performs the actual Claude ping. Keeping `run` separate from `install` makes the scheduled behavior manually testable.

`status` reports effective config, launch agent state, wake schedule state, last log path, and last run result if available.

`uninstall` unloads and removes the launch agent. It should only remove the `pmset` wake schedule when it matches the app's expected schedule, so it does not erase unrelated user wake settings.

## Configuration

The default config file is:

```text
~/.config/start-cc-5h-window/config.env
```

Default values:

```env
START_CC_5H_WINDOW_TIME=07:00
START_CC_5H_WINDOW_TIMEZONE=Australia/Melbourne
START_CC_5H_WINDOW_PROMPT=Reply with: ok
START_CC_5H_WINDOW_CLAUDE_BIN=claude
```

App-prefixed names avoid collisions if the config is sourced by shell tooling. The timezone records the intended schedule. `launchd` and `pmset` use the Mac's system timezone, so the app validates and warns when the configured timezone differs from the Mac's current timezone.

## Runtime Flow

The installed `launchd` agent runs:

```sh
start-cc-5h-window run
```

The command:

1. Loads `~/.config/start-cc-5h-window/config.env`.
2. Validates the configured time, timezone, prompt, and Claude binary.
3. Warns if the configured timezone differs from the Mac's current timezone.
4. Runs:

   ```sh
   claude --bare -p "$START_CC_5H_WINDOW_PROMPT"
   ```

5. Writes a timestamped log entry containing start time, effective config, exit code, stdout, stderr, and success or failure status.

The app does not retry by default. Retrying could consume more subscription usage, which conflicts with the core goal. Failures such as expired Claude auth, network issues, or late wake are logged and left for the user to inspect.

## Scheduling Behavior

`install` generates a `launchd` plist with `StartCalendarInterval` using the configured hour and minute.

`install` also schedules a wake event shortly before the configured run time, defaulting to 5 minutes earlier. With the default config, the Mac wakes at 6:55am and runs the Claude ping at 7:00am.

Because `pmset repeat` is system-wide, v1 should handle it conservatively:

- Inspect existing schedules with `pmset -g sched`.
- If there is no conflicting repeat wake schedule, apply the app wake schedule.
- If a repeat wake schedule already exists, show the existing schedule and refuse to overwrite it unless the user runs an explicit overwrite path.

This avoids accidentally changing unrelated personal or work wake settings.

## Repository Shape

```text
bin/start-cc-5h-window
share/com.local.start-cc-5h-window.plist.template
docs/superpowers/specs/2026-05-19-start-cc-5h-window-design.md
README.md
```

Responsibilities:

- `bin/start-cc-5h-window`: command dispatch, config validation, install/uninstall/status/run/configure behavior, logging, `launchctl`, and `pmset`.
- `share/com.local.start-cc-5h-window.plist.template`: readable `launchd` plist template populated during install.
- Config file: user-editable schedule and prompt settings.
- Logs: durable local run history under `~/Library/Logs/start-cc-5h-window/`.

## Testing and Verification

Verification should avoid mutating real scheduler state by default.

Required checks:

- Shell syntax check for the executable script.
- Dry-run install mode that prints generated config, plist, intended `launchctl` command, and intended `pmset` command without writing scheduler state.
- Unit-style checks for pure helper behavior when the shell script is structured for testability:
  - time validation
  - wake-time calculation
  - config loading
  - timezone detection
  - plist rendering

Manual verification:

- `start-cc-5h-window run` confirms Claude ping behavior.
- `start-cc-5h-window status` confirms agent, wake, and log state.
- A temporary schedule a few minutes in the future confirms `launchd` fires as expected.

## Open Implementation Notes

- The app name is intentionally specific to the 5-hour window, but docs should say "intended to start" rather than guarantee quota semantics. Anthropic can change how limits are counted.
- The first version should favor dry-run and explicit output before applying system scheduler changes.
- If `claude --bare -p` behavior changes for subscription plans, the implementation may need to switch to the least-consuming supported local Claude Code invocation.
