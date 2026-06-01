# start-cc-5h-window

`start-cc-5h-window` installs a local macOS schedule that runs a small Claude ping at the configured time. Its purpose is to start the 5-hour window before you begin work; it does not guarantee Anthropic quota semantics, because Anthropic can change how usage limits and reset windows are counted.

## Install

Run a dry-run first:

```sh
bin/start-cc-5h-window install --dry-run
```

The dry-run prints the config path, launch agent plist path, rendered plist, intended `launchctl` command, and intended `pmset` command without mutating scheduler state.

If the plan looks right, install it:

```sh
bin/start-cc-5h-window install
```

The install command creates a user LaunchAgent, then schedules the wake event with `pmset repeat`. `pmset repeat` requires root, so install runs it through `sudo` and will prompt for administrator credentials. A non-interactive install (no controlling terminal, or `sudo` configured to require one) cannot answer that prompt: the `pmset` step fails, install rolls back the LaunchAgent, and nothing is left scheduled. Run install from an interactive shell. The LaunchAgent itself does not require root.

## Claude Binary Resolution

`launchd` starts the scheduled job with a minimal `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`). Because `claude` is usually installed elsewhere (`~/.local/bin`, a Homebrew prefix, or a Node version-manager shim), the bare default `START_CC_5H_WINDOW_CLAUDE_BIN=claude` would not be found at run time. To avoid that, install writes an `EnvironmentVariables`/`PATH` key into the plist that prepends the resolved `claude` directory plus `~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`.

For maximum reliability set `START_CC_5H_WINDOW_CLAUDE_BIN` to an absolute path. `status` reports `CLAUDE_BIN_RESOLVED=` and warns when the configured binary cannot be resolved, so the scheduled job will not fail silently. Note that a Node version-manager install outside the standard prefixes may still require an absolute path or a custom `PATH`.

## Default Config

The default config is written to `~/.config/start-cc-5h-window/config.env`:

```sh
START_CC_5H_WINDOW_TIME=07:00
START_CC_5H_WINDOW_TIMEZONE=Australia/Melbourne
START_CC_5H_WINDOW_PROMPT=Reply with: ok
START_CC_5H_WINDOW_CLAUDE_BIN=claude
```

## Customize Time and Timezone

Edit `~/.config/start-cc-5h-window/config.env`, or pass environment variables when previewing an install:

```sh
START_CC_5H_WINDOW_TIME=08:30 \
START_CC_5H_WINDOW_TIMEZONE=Australia/Melbourne \
bin/start-cc-5h-window install --dry-run
```

`launchd` and `pmset` use the Mac's system timezone. The configured timezone records the intended schedule, and the app warns when it differs from the current system timezone.

## Test Run Without Waiting

Use `run` to invoke the Claude ping immediately:

```sh
bin/start-cc-5h-window run
```

To test the command without invoking real Claude, point `START_CC_5H_WINDOW_CLAUDE_BIN` at a stub executable:

```sh
START_CC_5H_WINDOW_CLAUDE_BIN=/path/to/claude-stub bin/start-cc-5h-window run
```

The test suite uses stubs for Claude and system tools; tests do not invoke real Claude.

## Status and Uninstall

Check the current config and launch agent state:

```sh
bin/start-cc-5h-window status
```

Remove the launch agent:

```sh
bin/start-cc-5h-window uninstall
```

Preview removal first:

```sh
bin/start-cc-5h-window uninstall --dry-run
```

`pmset repeat` is system-wide, so the app handles it conservatively. Install refuses to overwrite an existing repeat wake schedule unless you pass `--overwrite-pmset`, and uninstall only cancels the repeat wake schedule when it matches the app's expected schedule.

The schedule match parses the text output of `pmset -g sched`, whose formatting has varied across macOS versions and locales (24-hour vs. 12-hour times, day masks vs. "every day"). The app matches its own written form (`wakeorpoweron MTWRFSU HH:MM:00`) first and falls back to a 12-hour parse. On an unrecognized format the conservative direction holds -- it never cancels a schedule it cannot confirm as its own -- which means on some systems uninstall may leave the app's wake schedule in place. If `status` shows a lingering `PMSET_SCHEDULE` after uninstall, clear it manually with `sudo pmset repeat cancel`.
