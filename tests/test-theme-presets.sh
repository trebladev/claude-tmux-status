#!/bin/sh

set -eu

command -v tmux >/dev/null 2>&1 || {
    printf '%s\n' 'test-theme-presets: skipped (tmux not installed)'
    exit 0
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
SOCKET=claude-theme-presets-test-$$

cleanup() {
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT HUP INT TERM

CLAUDE_CONFIG_DIR="$TEST_DIR" \
    tmux -L "$SOCKET" -f /dev/null new-session -d -s theme-test

assert_theme() {
    theme=$1
    working=$2
    waiting=$3
    error=$4
    stopped=$5

    tmux -L "$SOCKET" set-option -g '@claude-status-theme' "$theme"
    tmux -L "$SOCKET" run-shell "$ROOT/claude-tmux-status.tmux"

    [ "$(tmux -L "$SOCKET" show-option -gqv '@claude-status-working-colour')" = "$working" ]
    [ "$(tmux -L "$SOCKET" show-option -gqv '@claude-status-waiting-colour')" = "$waiting" ]
    [ "$(tmux -L "$SOCKET" show-option -gqv '@claude-status-error-colour')" = "$error" ]
    [ "$(tmux -L "$SOCKET" show-option -gqv '@claude-status-stopped-colour')" = "$stopped" ]
}

assert_theme catppuccin-latte '#40a02b' '#df8e1d' '#d20f39' '#7c7f93'
assert_theme catppuccin-frappe '#a6d189' '#e5c890' '#e78284' '#949cbb'
assert_theme catppuccin-macchiato '#a6da95' '#eed49f' '#ed8796' '#939ab7'
assert_theme catppuccin-mocha '#a6e3a1' '#f9e2af' '#f38ba8' '#9399b2'

# The automatic preset follows Catppuccin's configured flavor.
tmux -L "$SOCKET" set-option -g '@catppuccin_flavor' frappe
assert_theme catppuccin '#a6d189' '#e5c890' '#e78284' '#949cbb'

# Custom mode preserves colours explicitly configured by the user.
tmux -L "$SOCKET" set-option -g '@claude-status-working-colour' '#123456'
tmux -L "$SOCKET" set-option -g '@claude-status-theme' custom
tmux -L "$SOCKET" run-shell "$ROOT/claude-tmux-status.tmux"
[ "$(tmux -L "$SOCKET" show-option -gqv '@claude-status-working-colour')" = '#123456' ]

printf '%s\n' 'test-theme-presets: ok'
