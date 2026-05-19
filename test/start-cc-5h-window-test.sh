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

output=$("$APP" help)
assert_contains "$output" "start-cc-5h-window install" "help lists install"
assert_contains "$output" "start-cc-5h-window run" "help lists run"

printf 'ok - smoke\n'
