#!/usr/bin/env bash

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAT_MARKER='#{E:@claude-tmux-status}'

if command -v node >/dev/null 2>&1; then
    node "$CURRENT_DIR/configure-hooks.js" uninstall
fi

if command -v tmux >/dev/null 2>&1; then
    for option in window-status-format window-status-current-format; do
        value="$(tmux show-option -gv "$option")"
        value=${value// $FORMAT_MARKER/}
        value=${value//$FORMAT_MARKER/}
        tmux set-option -gq "$option" "$value"
    done
    tmux set-option -gu '@claude-tmux-status' 2>/dev/null || true
    tmux set-option -gu '@claude-tmux-status-generation' 2>/dev/null || true
    tmux refresh-client -S >/dev/null 2>&1 || true
fi

printf '%s\n' 'claude-tmux-status hooks and tmux format marker removed.'
