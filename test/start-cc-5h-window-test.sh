#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
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

assert_not_exists() {
  path=$1
  message=$2
  [ ! -e "$path" ] || fail "$message"
}

assert_fails_contains() {
  message=$1
  needle=$2
  shift 2
  output=$("$@" 2>&1) && fail "$message"
  assert_contains "$output" "$needle" "$message"
}

output=$("$APP" help)
assert_contains "$output" "start-cc-5h-window install" "help lists install"
assert_contains "$output" "start-cc-5h-window run" "help lists run"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
HOME="$tmpdir/home"
mkdir -p "$HOME"
export HOME

output=$("$APP" status)
assert_contains "$output" "START_CC_5H_WINDOW_TIME=07:00" "status shows default time"
assert_contains "$output" "START_CC_5H_WINDOW_TIMEZONE=Australia/Melbourne" "status shows default timezone"
assert_contains "$output" "START_CC_5H_WINDOW_PROMPT=Reply with: ok" "status shows default prompt"
assert_contains "$output" "START_CC_5H_WINDOW_CLAUDE_BIN=claude" "status shows default claude bin"
assert_contains "$output" "CONFIG_DIR=$HOME/.config/start-cc-5h-window" "status shows config dir"
assert_contains "$output" "CONFIG_FILE=$HOME/.config/start-cc-5h-window/config.env" "status shows config file"
assert_contains "$output" "LOG_DIR=$HOME/Library/Logs/start-cc-5h-window" "status shows log dir"
assert_contains "$output" "LAUNCH_AGENT_FILE=$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "status shows launch agent file"

config_dir="$HOME/.config/start-cc-5h-window"
config_file="$config_dir/config.env"
mkdir -p "$config_dir"
cat >"$config_file" <<'CONFIG'
# test overrides
START_CC_5H_WINDOW_TIME=09:30
START_CC_5H_WINDOW_TIMEZONE=Etc/UTC
START_CC_5H_WINDOW_PROMPT=Configured prompt
START_CC_5H_WINDOW_CLAUDE_BIN=/usr/local/bin/claude
CONFIG

output=$("$APP" status)
assert_contains "$output" "START_CC_5H_WINDOW_TIME=09:30" "config overrides time"
assert_contains "$output" "START_CC_5H_WINDOW_TIMEZONE=Etc/UTC" "config overrides timezone"
assert_contains "$output" "START_CC_5H_WINDOW_PROMPT=Configured prompt" "config overrides prompt"
assert_contains "$output" "START_CC_5H_WINDOW_CLAUDE_BIN=/usr/local/bin/claude" "config overrides claude bin"

cat >"$config_file" <<'CONFIG'
START_CC_5H_WINDOW_TIME=99:00
CONFIG
assert_fails_contains "invalid time fails" "invalid START_CC_5H_WINDOW_TIME: 99:00" "$APP" status

cat >"$config_file" <<'CONFIG'
START_CC_5H_WINDOW_PROMPT=
CONFIG
assert_fails_contains "empty prompt fails" "missing START_CC_5H_WINDOW_PROMPT" "$APP" status

marker="$tmpdir/shell-code-ran"
cat >"$config_file" <<CONFIG
touch "$marker"
CONFIG
assert_fails_contains "shell code fails as malformed config" "invalid config line" "$APP" status
assert_not_exists "$marker" "config shell code was not executed"

dry_home="$tmpdir/dry-home"
HOME="$dry_home"
export HOME
stubs="$tmpdir/stubs"
calls="$tmpdir/calls"
mkdir -p "$stubs"
cat >"$stubs/launchctl" <<'STUB'
#!/bin/sh
mkdir -p "$(dirname "$LAUNCHCTL_CALLS")"
printf '%s\n' "$*" >>"$LAUNCHCTL_CALLS"
STUB
cat >"$stubs/pmset" <<'STUB'
#!/bin/sh
mkdir -p "$(dirname "$PMSET_CALLS")"
printf '%s\n' "$*" >>"$PMSET_CALLS"
STUB
chmod +x "$stubs/launchctl" "$stubs/pmset"
LAUNCHCTL_CALLS="$calls/launchctl"
PMSET_CALLS="$calls/pmset"
PATH="$stubs:$PATH"
export LAUNCHCTL_CALLS PMSET_CALLS PATH

output=$("$APP" install --dry-run)
assert_contains "$output" "CONFIG_FILE=$HOME/.config/start-cc-5h-window/config.env" "dry-run prints config file path"
assert_contains "$output" "launchctl bootstrap gui/" "dry-run prints launchctl bootstrap command"
assert_contains "$output" "pmset repeat wakeorpoweron" "dry-run prints pmset wake command"
assert_contains "$output" "<key>Hour</key>" "dry-run prints plist hour key"
assert_contains "$output" "<integer>7</integer>" "dry-run prints default hour"
assert_contains "$output" "<key>Minute</key>" "dry-run prints plist minute key"
assert_contains "$output" "<integer>0</integer>" "dry-run prints default minute"
assert_not_exists "$HOME/.config/start-cc-5h-window" "dry-run did not create config dir"
assert_not_exists "$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "dry-run did not create launch agent file"
assert_not_exists "$HOME/Library/Logs/start-cc-5h-window" "dry-run did not create log dir"
assert_not_exists "$LAUNCHCTL_CALLS" "dry-run did not call launchctl"
assert_not_exists "$PMSET_CALLS" "dry-run did not call pmset"

assert_fails_contains "unknown install flag fails" "unknown install flag: --bogus" "$APP" install --bogus

PATH="$ROOT_DIR/bin:$PATH"
export PATH
old_pwd=$(pwd)
cd "$tmpdir"
output=$(start-cc-5h-window install --dry-run)
cd "$old_pwd"
assert_contains "$output" "APP_PATH=$ROOT_DIR/bin/start-cc-5h-window" "PATH invocation resolves app path"
assert_contains "$output" "<string>$ROOT_DIR/bin/start-cc-5h-window</string>" "PATH invocation renders app path"

xml_home="$tmpdir/home & <xml>"
HOME="$xml_home"
mkdir -p "$HOME"
export HOME
output=$("$APP" install --dry-run)
assert_contains "$output" "home &amp; &lt;xml&gt;" "dry-run XML-escapes home path"
assert_contains "$output" "<string>$ROOT_DIR/bin/start-cc-5h-window</string>" "dry-run still renders app path"

assert_fails_contains "run placeholder is recognized" "run is not implemented yet" "$APP" run
assert_fails_contains "configure placeholder is recognized" "configure is not implemented yet" "$APP" configure
assert_fails_contains "uninstall placeholder is recognized" "uninstall is not implemented yet" "$APP" uninstall

printf 'ok - smoke\n'
