#!/bin/sh
# SC1007: `CDPATH= cd ...` resets CDPATH for the command; the space is intentional.
# shellcheck disable=SC1007
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
assert_contains "$output" "WAKE_TIME=06:55" "status shows computed wake time"
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
  print)
    case "${LAUNCHCTL_PRINT_MODE:-loaded}" in
      loaded) printf 'state = running\n' ;;
      missing) exit 113 ;;
    esac
    ;;
  bootstrap)
    [ "${LAUNCHCTL_FAIL_BOOTSTRAP:-false}" = true ] && exit 77
    exit 0
    ;;
  bootout) exit 1 ;;
esac
STUB
cat >"$stubs/pmset" <<'STUB'
#!/bin/sh
mkdir -p "$(dirname "$PMSET_CALLS")"
printf '%s\n' "$*" >>"$PMSET_CALLS"
if [ "$1" = "-g" ] && [ "$2" = "sched" ]; then
  [ "${PMSET_FAIL_SCHED:-false}" = true ] && exit 1
  [ "${PMSET_SCHED_OUTPUT+x}" ] && printf '%s\n' "$PMSET_SCHED_OUTPUT"
  exit 0
fi
[ "${PMSET_FAIL_REPEAT:-false}" = true ] && [ "$1" = "repeat" ] && exit 64
exit 0
STUB
cat >"$stubs/id" <<'STUB'
#!/bin/sh
case "$1" in
  -u) printf '%s\n' 501 ;;
  *) printf 'id stub only supports -u\n' >&2; exit 2 ;;
esac
STUB
cat >"$stubs/sudo" <<'STUB'
#!/bin/sh
exec "$@"
STUB
chmod +x "$stubs/launchctl" "$stubs/pmset" "$stubs/id" "$stubs/sudo"
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
assert_contains "$output" "<key>EnvironmentVariables</key>" "dry-run plist sets EnvironmentVariables"
assert_contains "$output" "<key>PATH</key>" "dry-run plist sets PATH"
assert_contains "$output" "/.local/bin" "dry-run plist PATH includes user bin dir"
assert_contains "$output" "PATH_ENV=" "dry-run plan prints PATH_ENV"
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

pmset_fail_install_home="$tmpdir/pmset-fail-install-home"
HOME="$pmset_fail_install_home"
export HOME
PMSET_FAIL_REPEAT=true
export PMSET_FAIL_REPEAT
PMSET_SCHED_OUTPUT=
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
if "$APP" install >/dev/null 2>&1; then
  fail "install fails when pmset repeat fails"
fi
assert_contains "$(cat "$LAUNCHCTL_CALLS")" "bootstrap gui/501 $HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "install loads launch agent before pmset"
assert_contains "$(cat "$PMSET_CALLS")" "repeat wakeorpoweron MTWRFSU 06:55:00" "install attempts pmset"
assert_contains "$(cat "$LAUNCHCTL_CALLS")" "bootout gui/501 $HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "install rolls back launch agent after pmset failure"
assert_not_exists "$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "install removes plist after pmset failure"
unset PMSET_FAIL_REPEAT

launchctl_fail_install_home="$tmpdir/launchctl-fail-install-home"
HOME="$launchctl_fail_install_home"
export HOME
LAUNCHCTL_FAIL_BOOTSTRAP=true
export LAUNCHCTL_FAIL_BOOTSTRAP
PMSET_SCHED_OUTPUT=
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
if "$APP" install >/dev/null 2>&1; then
  fail "install fails when launchctl bootstrap fails"
fi
assert_contains "$(cat "$LAUNCHCTL_CALLS")" "bootstrap gui/501 $HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "install attempts launchctl bootstrap"
assert_not_exists "$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "install rolls back plist after launchctl failure"
assert_contains "$(cat "$PMSET_CALLS")" "-g sched" "install checks pmset before launchctl failure"
pmset_calls=$(cat "$PMSET_CALLS")
case "$pmset_calls" in
  *"repeat wakeorpoweron"*) fail "install does not set pmset after launchctl failure" ;;
esac
unset LAUNCHCTL_FAIL_BOOTSTRAP

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
assert_contains "$output" "existing pmset repeat schedule" "install warns about existing pmset repeat schedule"
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
assert_contains "$output" "existing pmset repeat schedule" "install treats repeat poweron as conflict"
assert_not_exists "$LAUNCHCTL_CALLS" "repeat poweron conflict does not call launchctl"
pmset_calls=$(cat "$PMSET_CALLS")
case "$pmset_calls" in
  *"repeat wakeorpoweron"*) fail "install did not overwrite conflicting poweron schedule" ;;
esac

sleep_conflict_home="$tmpdir/sleep-conflict-home"
HOME="$sleep_conflict_home"
export HOME
PMSET_SCHED_OUTPUT='Repeating power events:
  sleep at 11:00PM every day'
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
output=$("$APP" install 2>&1) && fail "install fails on existing pmset repeat sleep schedule"
assert_contains "$output" "existing pmset repeat schedule" "install treats repeat sleep as conflict"
assert_not_exists "$LAUNCHCTL_CALLS" "repeat sleep conflict does not call launchctl"
pmset_calls=$(cat "$PMSET_CALLS")
case "$pmset_calls" in
  *"repeat wakeorpoweron"*) fail "install did not overwrite conflicting sleep schedule" ;;
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

resolve_home="$tmpdir/resolve-home"
HOME="$resolve_home"
mkdir -p "$HOME"
export HOME
resolve_bin_dir="$tmpdir/claude-bin-dir"
mkdir -p "$resolve_bin_dir"
printf '#!/bin/sh\n' >"$resolve_bin_dir/claude"
chmod +x "$resolve_bin_dir/claude"
START_CC_5H_WINDOW_CLAUDE_BIN="$resolve_bin_dir/claude"
export START_CC_5H_WINDOW_CLAUDE_BIN
output=$("$APP" install --dry-run)
assert_contains "$output" "PATH_ENV=$resolve_bin_dir:" "dry-run plan PATH leads with resolved claude bin dir"
assert_contains "$output" "<string>$resolve_bin_dir:" "dry-run plist PATH leads with resolved claude bin dir"
unset START_CC_5H_WINDOW_CLAUDE_BIN

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
assert_contains "$log_content" "timezone_warning=configured timezone Australia/Melbourne does not match current timezone Etc/UTC" "run log records IANA timezone mismatch"
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
assert_contains "$fallback_log" "timezone_warning=none (current timezone AEDT not comparable" "run does not warn on non-comparable abbreviation"
case "$fallback_log" in
  *"OUT_NO_NLstderr:"*) fail "run log separates stdout from stderr" ;;
esac
case "$fallback_log" in
  *"ERR_NO_NLexit_code=0"*) fail "run log separates stderr from exit code" ;;
esac
assert_not_exists "$HOME/Library/Logs/start-cc-5h-window"/*.stdout "run removes stdout temp file"
assert_not_exists "$HOME/Library/Logs/start-cc-5h-window"/*.stderr "run removes stderr temp file"
unset SYSTEMSETUP_MODE

status_home="$tmpdir/status-home"
HOME="$status_home"
mkdir -p "$HOME/Library/Logs/start-cc-5h-window"
export HOME
cat >"$HOME/Library/Logs/start-cc-5h-window/run-20260101070000-1.log" <<'LOG'
old
LOG
cat >"$HOME/Library/Logs/start-cc-5h-window/run-20260101080000-2.log" <<'LOG'
new
LOG
PMSET_SCHED_OUTPUT='Repeating power events:
  wakeorpoweron MTWRFSU 06:55:00'
LAUNCHCTL_PRINT_MODE=loaded
export PMSET_SCHED_OUTPUT LAUNCHCTL_PRINT_MODE
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
output=$("$APP" status)
assert_contains "$output" "CONFIG_FILE=$HOME/.config/start-cc-5h-window/config.env" "status shows config file path"
assert_contains "$output" "LAUNCH_AGENT_FILE=$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "status shows plist path"
assert_contains "$output" "LOG_DIR=$HOME/Library/Logs/start-cc-5h-window" "status shows log dir"
assert_contains "$output" "LAUNCH_AGENT_LOADED=loaded" "status shows loaded launch agent"
assert_contains "$output" "PMSET_SCHEDULE=wakeorpoweron MTWRFSU 06:55:00" "status summarizes pmset schedule"
assert_contains "$output" "LATEST_LOG=$HOME/Library/Logs/start-cc-5h-window/run-20260101080000-2.log" "status shows newest run log"
assert_contains "$output" "CLAUDE_BIN_RESOLVED=$stubs/claude" "status resolves claude bin on PATH"

unresolved_status_home="$tmpdir/unresolved-status-home"
HOME="$unresolved_status_home"
mkdir -p "$HOME/.config/start-cc-5h-window"
export HOME
cat >"$HOME/.config/start-cc-5h-window/config.env" <<'CONFIG'
START_CC_5H_WINDOW_CLAUDE_BIN=/nonexistent/claude
CONFIG
output=$("$APP" status 2>/dev/null)
assert_contains "$output" "CLAUDE_BIN_RESOLVED=unresolved" "status flags unresolvable claude bin"
status_warning=$("$APP" status 2>&1 >/dev/null)
assert_contains "$status_warning" "is not resolvable on PATH" "status emits unresolvable warning to stderr"
HOME="$status_home"
export HOME
assert_contains "$(cat "$LAUNCHCTL_CALLS")" "print gui/501/com.local.start-cc-5h-window" "status checks launch agent state"
assert_contains "$(cat "$PMSET_CALLS")" "-g sched" "status checks pmset schedule"

LAUNCHCTL_PRINT_MODE=missing
export LAUNCHCTL_PRINT_MODE
rm -f "$LAUNCHCTL_CALLS"
output=$("$APP" status)
assert_contains "$output" "LAUNCH_AGENT_LOADED=not loaded" "status shows missing launch agent"

configure_home="$tmpdir/configure-home"
HOME="$configure_home"
mkdir -p "$HOME/.config/start-cc-5h-window"
export HOME
cat >"$HOME/.config/start-cc-5h-window/config.env" <<'CONFIG'
START_CC_5H_WINDOW_TIME=08:15
START_CC_5H_WINDOW_PROMPT=Existing prompt
CONFIG
START_CC_5H_WINDOW_TIME=10:45
START_CC_5H_WINDOW_TIMEZONE=Etc/UTC
START_CC_5H_WINDOW_CLAUDE_BIN=/opt/claude
export START_CC_5H_WINDOW_TIME START_CC_5H_WINDOW_TIMEZONE START_CC_5H_WINDOW_CLAUDE_BIN
"$APP" configure >/dev/null
configured=$(cat "$HOME/.config/start-cc-5h-window/config.env")
assert_contains "$configured" "START_CC_5H_WINDOW_TIME=10:45" "configure applies time override"
assert_contains "$configured" "START_CC_5H_WINDOW_TIMEZONE=Etc/UTC" "configure applies timezone override"
assert_contains "$configured" "START_CC_5H_WINDOW_PROMPT=Existing prompt" "configure preserves prompt"
assert_contains "$configured" "START_CC_5H_WINDOW_CLAUDE_BIN=/opt/claude" "configure applies claude bin override"
unset START_CC_5H_WINDOW_TIME START_CC_5H_WINDOW_TIMEZONE START_CC_5H_WINDOW_CLAUDE_BIN

new_configure_home="$tmpdir/new-configure-home"
HOME="$new_configure_home"
export HOME
"$APP" configure >/dev/null
assert_exists "$HOME/.config/start-cc-5h-window/config.env" "configure creates config file"
assert_contains "$(cat "$HOME/.config/start-cc-5h-window/config.env")" "START_CC_5H_WINDOW_TIME=07:00" "configure writes complete defaults"

invalid_configure_home="$tmpdir/invalid-configure-home"
HOME="$invalid_configure_home"
export HOME
START_CC_5H_WINDOW_TIME=25:00
export START_CC_5H_WINDOW_TIME
assert_fails_contains "configure validates resulting config" "invalid START_CC_5H_WINDOW_TIME: 25:00" "$APP" configure
unset START_CC_5H_WINDOW_TIME

newline_configure_home="$tmpdir/newline-configure-home"
HOME="$newline_configure_home"
export HOME
START_CC_5H_WINDOW_PROMPT='line one
line two'
export START_CC_5H_WINDOW_PROMPT
assert_fails_contains "configure rejects newline prompt" "START_CC_5H_WINDOW_PROMPT must not contain newlines" "$APP" configure
unset START_CC_5H_WINDOW_PROMPT

uninstall_home="$tmpdir/uninstall-home"
HOME="$uninstall_home"
mkdir -p "$HOME/Library/LaunchAgents"
printf 'plist\n' >"$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist"
export HOME
PMSET_SCHED_OUTPUT='Repeating power events:
  wakeorpoweron MTWRFSU 06:55:00'
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
output=$("$APP" uninstall --dry-run)
assert_contains "$output" "launchctl bootout gui/501 $HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "uninstall dry-run prints bootout"
assert_contains "$output" "rm $HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "uninstall dry-run prints plist removal"
assert_contains "$output" "pmset repeat cancel" "uninstall dry-run prints matching pmset cancellation"
assert_not_exists "$LAUNCHCTL_CALLS" "uninstall dry-run does not call launchctl"
assert_exists "$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "uninstall dry-run keeps plist"

rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
"$APP" uninstall >/dev/null
assert_contains "$(cat "$LAUNCHCTL_CALLS")" "bootout gui/501 $HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "uninstall calls launchctl bootout"
assert_contains "$(cat "$PMSET_CALLS")" "-g sched" "uninstall inspects pmset schedule"
assert_contains "$(cat "$PMSET_CALLS")" "repeat cancel" "uninstall clears matching pmset schedule"
assert_not_exists "$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "uninstall removes plist"

invalid_prompt_uninstall_home="$tmpdir/invalid-prompt-uninstall-home"
HOME="$invalid_prompt_uninstall_home"
mkdir -p "$HOME/.config/start-cc-5h-window" "$HOME/Library/LaunchAgents"
cat >"$HOME/.config/start-cc-5h-window/config.env" <<'CONFIG'
START_CC_5H_WINDOW_PROMPT=
CONFIG
printf 'plist\n' >"$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist"
export HOME
PMSET_SCHED_OUTPUT='Repeating power events:
  wakeorpoweron MTWRFSU 06:55:00'
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
"$APP" uninstall >/dev/null
assert_contains "$(cat "$LAUNCHCTL_CALLS")" "bootout gui/501 $HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "uninstall ignores invalid prompt for launchctl cleanup"
assert_contains "$(cat "$PMSET_CALLS")" "repeat cancel" "uninstall ignores invalid prompt for matching pmset cleanup"
assert_not_exists "$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "uninstall removes plist with invalid prompt"

normalized_uninstall_home="$tmpdir/normalized-uninstall-home"
HOME="$normalized_uninstall_home"
mkdir -p "$HOME/Library/LaunchAgents"
printf 'plist\n' >"$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist"
export HOME
PMSET_SCHED_OUTPUT='Repeating power events:
  wakepoweron at 6:55AM every day'
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
"$APP" uninstall >/dev/null
assert_contains "$(cat "$PMSET_CALLS")" "repeat cancel" "uninstall clears normalized matching pmset schedule"

combined_uninstall_home="$tmpdir/combined-uninstall-home"
HOME="$combined_uninstall_home"
mkdir -p "$HOME/Library/LaunchAgents"
printf 'plist\n' >"$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist"
export HOME
PMSET_SCHED_OUTPUT='Repeating power events:
  wakepoweron at 6:55AM every day
  sleep at 5:00PM every day'
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
output=$("$APP" uninstall 2>&1)
assert_contains "$output" "pmset repeat wake schedule does not match 06:55" "uninstall warns about combined pmset schedule"
pmset_calls=$(cat "$PMSET_CALLS")
case "$pmset_calls" in
  *"repeat cancel"*) fail "uninstall does not remove combined pmset schedule" ;;
esac

unrelated_uninstall_home="$tmpdir/unrelated-uninstall-home"
HOME="$unrelated_uninstall_home"
mkdir -p "$HOME/Library/LaunchAgents"
printf 'plist\n' >"$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist"
export HOME
PMSET_SCHED_OUTPUT='Repeating power events:
  wakeorpoweron MTWRFSU 06:45:00'
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
output=$("$APP" uninstall 2>&1)
assert_contains "$output" "pmset repeat wake schedule does not match 06:55" "uninstall warns about unrelated pmset schedule"
pmset_calls=$(cat "$PMSET_CALLS")
case "$pmset_calls" in
  *"repeat cancel"*) fail "uninstall does not remove unrelated pmset schedule" ;;
esac

same_time_unrelated_uninstall_home="$tmpdir/same-time-unrelated-uninstall-home"
HOME="$same_time_unrelated_uninstall_home"
mkdir -p "$HOME/Library/LaunchAgents"
printf 'plist\n' >"$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist"
export HOME
PMSET_SCHED_OUTPUT='Repeating power events:
  wake at 06:55 every day'
export PMSET_SCHED_OUTPUT
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
output=$("$APP" uninstall 2>&1)
assert_contains "$output" "pmset repeat wake schedule does not match 06:55" "uninstall warns about same-time unrelated pmset schedule"
pmset_calls=$(cat "$PMSET_CALLS")
case "$pmset_calls" in
  *"repeat cancel"*) fail "uninstall does not remove same-time unrelated pmset schedule" ;;
esac

pmset_fail_uninstall_home="$tmpdir/pmset-fail-uninstall-home"
HOME="$pmset_fail_uninstall_home"
mkdir -p "$HOME/Library/LaunchAgents"
printf 'plist\n' >"$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist"
export HOME
PMSET_FAIL_SCHED=true
export PMSET_FAIL_SCHED
rm -f "$LAUNCHCTL_CALLS" "$PMSET_CALLS"
output=$("$APP" uninstall 2>&1)
assert_contains "$output" "unable to inspect pmset schedule" "uninstall warns when pmset inspection fails"
assert_not_exists "$HOME/Library/LaunchAgents/com.local.start-cc-5h-window.plist" "uninstall still removes plist when pmset inspection fails"
unset PMSET_FAIL_SCHED

printf 'ok - smoke\n'
