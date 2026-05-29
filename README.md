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

The install command creates a user LaunchAgent, then schedules the wake event with `pmset repeat`. On macOS, changing the repeat wake schedule may prompt for administrator credentials through `sudo`; the LaunchAgent itself remains installed for your user.

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
