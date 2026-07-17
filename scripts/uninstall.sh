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
    bound_key="$(tmux show-option -gqv '@claude-search-bound-key')"
    if [ -n "$bound_key" ]; then
        binding="$(tmux list-keys -T prefix "$bound_key" 2>/dev/null || true)"
        case "$binding" in
            *"$CURRENT_DIR/search-popup.sh"*)
                tmux unbind-key "$bound_key" 2>/dev/null || true
                ;;
        esac
    fi
    tmux set-option -gu '@claude-search-bound-key' 2>/dev/null || true
    tmux set-option -gu '@claude-search-key' 2>/dev/null || true
    tmux refresh-client -S >/dev/null 2>&1 || true
fi

printf '%s\n' 'claude-tmux-status hooks and tmux format marker removed.'
