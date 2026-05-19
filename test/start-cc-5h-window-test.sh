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

printf 'ok - smoke\n'
