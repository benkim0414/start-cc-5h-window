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

assert_exists() {
  path=$1
  message=$2
  [ -e "$path" ] || fail "$message"
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
case "$1" in
  bootout) exit 1 ;;
esac
STUB
cat >"$stubs/pmset" <<'STUB'
#!/bin/sh
mkdir -p "$(dirname "$PMSET_CALLS")"
printf '%s\n' "$*" >>"$PMSET_CALLS"
if [ "$1" = "-g" ] && [ "$2" = "sched" ]; then
  [ "${PMSET_SCHED_OUTPUT+x}" ] && printf '%s\n' "$PMSET_SCHED_OUTPUT"
fi
STUB
cat >"$stubs/id" <<'STUB'
#!/bin/sh
case "$1" in
  -u) printf '%s\n' 501 ;;
  *) printf 'id stub only supports -u\n' >&2; exit 2 ;;
esac
STUB
chmod +x "$stubs/launchctl" "$stubs/pmset" "$stubs/id"
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

install_home="$tmpdir/install-home"
HOME="$install_home"
export HOME
PMSET_SCHED_OUTPUT=
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
output=$("$APP" install)
assert_exists "$HOME/.config/start-cc-5h-window" "install creates config dir"
assert_exists "$HOME/.config/start-cc-5h-window/config.env" "install creates config file"
assert_exists "$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "install creates launch agent plist"
assert_exists "$HOME/Library/Logs/start-cc-5h-window" "install creates log dir"
assert_contains "$(cat "$HOME/.config/start-cc-5h-window/config.env")" "START_CC_5H_WINDOW_TIME=07:00" "install writes default time"
assert_contains "$(cat "$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist")" "<integer>7</integer>" "install writes plist hour"
assert_contains "$(cat "$LAUNCHCTL_CALLS")" "bootout gui/501 $HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "install calls launchctl bootout"
assert_contains "$(cat "$LAUNCHCTL_CALLS")" "bootstrap gui/501 $HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "install calls launchctl bootstrap"
assert_contains "$(cat "$LAUNCHCTL_CALLS")" "enable gui/501/com.local.start-cc-5h-window" "install calls launchctl enable"
assert_contains "$(cat "$PMSET_CALLS")" "-g sched" "install checks pmset schedule"
assert_contains "$(cat "$PMSET_CALLS")" "repeat wakeorpoweron MTWRFSU 06:55:00" "install sets pmset repeat when no conflict"

existing_config_home="$tmpdir/existing-config-home"
HOME="$existing_config_home"
export HOME
mkdir -p "$HOME/.config/start-cc-5h-window"
cat >"$HOME/.config/start-cc-5h-window/config.env" <<'CONFIG'
START_CC_5H_WINDOW_TIME=08:15
START_CC_5H_WINDOW_PROMPT=Existing prompt
CONFIG
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
"$APP" install >/dev/null
assert_contains "$(cat "$HOME/.config/start-cc-5h-window/config.env")" "START_CC_5H_WINDOW_PROMPT=Existing prompt" "install preserves existing config"

conflict_home="$tmpdir/conflict-home"
HOME="$conflict_home"
export HOME
PMSET_SCHED_OUTPUT='Repeating power events:
  wakeorpoweron at 06:45 every day'
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
output=$("$APP" install 2>&1) && fail "install fails on existing pmset repeat wake schedule"
assert_contains "$output" "existing repeat wake schedule" "install warns about existing pmset repeat wake schedule"
assert_contains "$output" "wakeorpoweron at 06:45 every day" "install prints existing pmset schedule"
assert_contains "$(cat "$PMSET_CALLS")" "-g sched" "install checks conflicting pmset schedule"
assert_not_exists "$HOME/.config/start-cc-5h-window" "pmset conflict does not create config dir"
assert_not_exists "$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "pmset conflict does not create plist"
assert_not_exists "$LAUNCHCTL_CALLS" "pmset conflict does not call launchctl"
pmset_calls=$(cat "$PMSET_CALLS")
case "$pmset_calls" in
  *"repeat wakeorpoweron"*) fail "install did not overwrite conflicting pmset schedule" ;;
esac

poweron_conflict_home="$tmpdir/poweron-conflict-home"
HOME="$poweron_conflict_home"
export HOME
PMSET_SCHED_OUTPUT='Repeating power events:
  poweron at 06:45 every day'
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
output=$("$APP" install 2>&1) && fail "install fails on existing pmset repeat poweron schedule"
assert_contains "$output" "existing repeat wake schedule" "install treats repeat poweron as conflict"
assert_not_exists "$LAUNCHCTL_CALLS" "repeat poweron conflict does not call launchctl"
pmset_calls=$(cat "$PMSET_CALLS")
case "$pmset_calls" in
  *"repeat wakeorpoweron"*) fail "install did not overwrite conflicting poweron schedule" ;;
esac

HOME="$conflict_home"
export HOME
PMSET_SCHED_OUTPUT='Repeating power events:
  wakeorpoweron at 06:45 every day'
export PMSET_SCHED_OUTPUT
rm -f "$PMSET_CALLS"
output=$("$APP" install --overwrite-pmset 2>&1)
assert_contains "$(cat "$PMSET_CALLS")" "repeat wakeorpoweron MTWRFSU 06:55:00" "overwrite install updates pmset repeat"

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

run_home="$tmpdir/run-home"
HOME="$run_home"
mkdir -p "$HOME"
export HOME
claude_args="$tmpdir/claude-args"
cat >"$stubs/claude" <<STUB
#!/bin/sh
: >"$claude_args"
for arg do
  printf '<%s>\n' "\$arg" >>"$claude_args"
done
printf 'ok\n'
STUB
cat >"$stubs/systemsetup" <<'STUB'
#!/bin/sh
case "${SYSTEMSETUP_MODE:-success}" in
  success)
    if [ "$1" = "-gettimezone" ]; then
      printf 'Time Zone: Etc/UTC\n'
      exit 0
    fi
    ;;
  fail)
    printf 'You need administrator access to run this tool... exiting!\n' >&2
    exit 1
    ;;
esac
exit 2
STUB
cat >"$stubs/date" <<'STUB'
#!/bin/sh
case "$1" in
  +%Z) printf 'AEDT\n' ;;
  *) /bin/date "$@" ;;
esac
STUB
chmod +x "$stubs/claude" "$stubs/systemsetup" "$stubs/date"
PATH="$stubs:$PATH"
export PATH

output=$("$APP" run)
assert_contains "$output" "ok" "run prints claude stdout"
expected_args=$(printf '<--bare>\n<-p>\n<Reply with: ok>')
[ "$(cat "$claude_args")" = "$expected_args" ] || fail "run invokes claude with bare prompt"
log_dir="$HOME/Library/Logs/start-cc-5h-window"
set -- "$log_dir"/run-*.log
[ "$#" -eq 1 ] || fail "run created exactly one log file"
assert_exists "$1" "run created log file"
log_content=$(cat "$1")
assert_contains "$log_content" "configured_time=07:00" "run log includes configured time"
assert_contains "$log_content" "configured_timezone=Australia/Melbourne" "run log includes configured timezone"
assert_contains "$log_content" "command_path=claude" "run log includes command path"
assert_contains "$log_content" "stdout:" "run log includes stdout section"
assert_contains "$log_content" "ok" "run log includes claude stdout"
assert_contains "$log_content" "stderr:" "run log includes stderr section"
assert_contains "$log_content" "timezone_warning=" "run log includes timezone warning"
assert_contains "$log_content" "exit_code=0" "run log includes success exit code"
assert_contains "$log_content" "status=success" "run log includes success status"

failure_home="$tmpdir/run-failure-home"
HOME="$failure_home"
mkdir -p "$HOME"
export HOME
failing_claude="$tmpdir/failing-claude"
cat >"$failing_claude" <<'STUB'
#!/bin/sh
printf 'nope\n' >&2
exit 7
STUB
chmod +x "$failing_claude"
START_CC_5H_WINDOW_CLAUDE_BIN="$failing_claude"
export START_CC_5H_WINDOW_CLAUDE_BIN
if "$APP" run >/dev/null 2>&1; then
  fail "run returns nonzero claude exit"
else
  run_code=$?
fi
[ "$run_code" -eq 7 ] || fail "run returned claude exit code"
set -- "$HOME/Library/Logs/start-cc-5h-window"/run-*.log
[ "$#" -eq 1 ] || fail "failed run created exactly one log file"
failure_log=$(cat "$1")
assert_contains "$failure_log" "stderr:" "failed run log includes stderr section"
assert_contains "$failure_log" "nope" "failed run log includes claude stderr"
assert_contains "$failure_log" "exit_code=7" "failed run log includes failure exit code"
assert_contains "$failure_log" "status=failure" "failed run log includes failure status"
unset START_CC_5H_WINDOW_CLAUDE_BIN

fallback_home="$tmpdir/run-fallback-home"
HOME="$fallback_home"
mkdir -p "$HOME"
export HOME
SYSTEMSETUP_MODE=fail
export SYSTEMSETUP_MODE
cat >"$stubs/claude" <<'STUB'
#!/bin/sh
printf 'OUT_NO_NL'
printf 'ERR_NO_NL' >&2
STUB
chmod +x "$stubs/claude"
output=$("$APP" run 2>"$tmpdir/no-newline-stderr")
assert_contains "$output" "OUT_NO_NL" "run prints stdout without trailing newline"
assert_contains "$(cat "$tmpdir/no-newline-stderr")" "ERR_NO_NL" "run prints stderr without trailing newline"
set -- "$HOME/Library/Logs/start-cc-5h-window"/run-*.log
[ "$#" -eq 1 ] || fail "fallback run created exactly one log file"
fallback_log=$(cat "$1")
assert_contains "$fallback_log" "current_timezone=AEDT" "run falls back when systemsetup fails"
case "$fallback_log" in
  *"OUT_NO_NLstderr:"*) fail "run log separates stdout from stderr" ;;
esac
case "$fallback_log" in
  *"ERR_NO_NLexit_code=0"*) fail "run log separates stderr from exit code" ;;
esac
assert_not_exists "$HOME/Library/Logs/start-cc-5h-window"/*.stdout "run removes stdout temp file"
assert_not_exists "$HOME/Library/Logs/start-cc-5h-window"/*.stderr "run removes stderr temp file"
unset SYSTEMSETUP_MODE

assert_fails_contains "configure placeholder is recognized" "configure is not implemented yet" "$APP" configure
assert_fails_contains "uninstall placeholder is recognized" "uninstall is not implemented yet" "$APP" uninstall

printf 'ok - smoke\n'
