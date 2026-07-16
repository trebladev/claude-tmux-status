#!/bin/sh

set -eu

command -v tmux >/dev/null 2>&1 || {
    printf '%s\n' 'test-catppuccin-integration: skipped (tmux not installed)'
    exit 0
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
SOCKET=claude-catppuccin-test-$$

cleanup() {
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT HUP INT TERM

CLAUDE_CONFIG_DIR="$TEST_DIR" \
    tmux -L "$SOCKET" -f /dev/null new-session -d -s catppuccin-test

separator='#[fg=#111111,reverse]#[none]'
tmux -L "$SOCKET" set-option -g '@catppuccin_window_right_separator' "$separator"
tmux -L "$SOCKET" set-option -g '@catppuccin_window_current_right_separator' "$separator"
tmux -L "$SOCKET" set-option -g window-status-format "#[bg=#222222] #W$separator"
tmux -L "$SOCKET" set-option -g window-status-current-format "#[bg=#333333] #W$separator"

tmux -L "$SOCKET" run-shell "$ROOT/claude-tmux-status.tmux"

marker='#{E:@claude-tmux-status}'
inactive=$(tmux -L "$SOCKET" show-option -gv window-status-format)
active=$(tmux -L "$SOCKET" show-option -gv window-status-current-format)

case "$inactive:$active" in
    *"$marker$separator"*:*"$marker$separator"*) ;;
    *) exit 1 ;;
esac
[ "$(tmux -L "$SOCKET" show-option -gqv '@claude-status-embedded')" = on ]

# Reloading keeps exactly one marker in the embedded position.
tmux -L "$SOCKET" run-shell "$ROOT/claude-tmux-status.tmux"
inactive=$(tmux -L "$SOCKET" show-option -gv window-status-format)
remainder=${inactive#*"$marker"}
case "$remainder" in
    *"$marker"*) exit 1 ;;
esac
case "$inactive" in
    *"$marker$separator"*) ;;
    *) exit 1 ;;
esac

printf '%s\n' 'test-catppuccin-integration: ok'
