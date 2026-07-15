#!/bin/sh

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/state"

printf '%s\n' \
    '#!/bin/sh' \
    'case "$1" in' \
    '  list-panes) printf "%b" "$FAKE_PANES" ;;' \
    '  show-option) exit 0 ;;' \
    '  *) exit 1 ;;' \
    'esac' >"$TEST_DIR/bin/tmux"
chmod +x "$TEST_DIR/bin/tmux"

# The fake tmux option lookup returns empty, exercising the plugin defaults.
write_state() {
    printf '%s\t%s\t%s\t%s\n' "$2" 1 "$$" "$3" >"$TEST_DIR/state/pane-$1"
}

write_state 1 working 101
write_state 2 waiting 202

output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='%1|101\n%2|202\n' \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/render-status.sh" '@1')
[ "$output" = '#[fg=#ffff00]●#[default]' ]

write_state 2 error 202
output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='%1|101\n%2|202\n' \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/render-status.sh" '@1')
[ "$output" = '#[fg=colour196]●#[default]' ]

# A dead Claude PID degrades to stopped instead of leaving a stale green dot.
printf 'working\t1\t99999999\t101\n' >"$TEST_DIR/state/pane-1"
output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='%1|101\n' \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/render-status.sh" '@1')
[ "$output" = '#[fg=colour244]●#[default]' ]

# A state file from an old tmux server is ignored when pane_pid differs.
output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='%1|999\n' \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/render-status.sh" '@1')
[ -z "$output" ]

printf '%s\n' 'test-render: ok'
