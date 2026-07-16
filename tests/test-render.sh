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
    '  show-option)' \
    '    case "${3:-}" in' \
    '      @claude-status-show-stopped) printf "%s" "${FAKE_SHOW_STOPPED:-}" ;;' \
    '      @claude-status-auto-contrast) printf "%s" "${FAKE_AUTO_CONTRAST:-}" ;;' \
    '      status-style) printf "%s" "${FAKE_STATUS_STYLE:-}" ;;' \
    '    esac' \
    '    ;;' \
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

# A green working dot falls back to the status text colour on a green bar.
output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='%1|101\n' \
    FAKE_STATUS_STYLE='bg=green,fg=black' \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/render-status.sh" '@1')
[ "$output" = '#[fg=black]●#[default]' ]

# Automatic contrast can be disabled when exact configured colours are needed.
output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='%1|101\n' \
    FAKE_STATUS_STYLE='bg=green,fg=black' \
    FAKE_AUTO_CONTRAST=off \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/render-status.sh" '@1')
[ "$output" = '#[fg=colour40]●#[default]' ]

# True-colour values are compared as RGB rather than as raw strings.
write_state 2 waiting 202
output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='%2|202\n' \
    FAKE_STATUS_STYLE='bg=#ffff00,fg=#000000' \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/render-status.sh" '@1')
[ "$output" = '#[fg=#000000]●#[default]' ]

# Embedded markers preserve the surrounding theme background and separator.
output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='%2|202\n' \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/render-status.sh" '@1' generation on)
[ "$output" = ' #[fg=#ffff00]● ' ]

# A dead Claude PID is hidden instead of leaving a stale status dot.
printf 'working\t1\t99999999\t101\n' >"$TEST_DIR/state/pane-1"
output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='%1|101\n' \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/render-status.sh" '@1')
[ -z "$output" ]

# Users can opt back into the stopped indicator explicitly.
output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='%1|101\n' \
    FAKE_SHOW_STOPPED=on \
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
