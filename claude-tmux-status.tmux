#!/usr/bin/env bash

# tmux entrypoint. It installs the Claude Code lifecycle hooks and appends one
# expandable marker to both inactive and active window labels.

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAT_MARKER='#{E:@claude-tmux-status}'

set_default_option() {
    local option="$1"
    local default_value="$2"

    if [ -z "$(tmux show-option -gqv "$option")" ]; then
        tmux set-option -gq "$option" "$default_value"
    fi
}

set_colour_options() {
    tmux set-option -gq '@claude-status-working-colour' "$1"
    tmux set-option -gq '@claude-status-waiting-colour' "$2"
    tmux set-option -gq '@claude-status-error-colour' "$3"
    tmux set-option -gq '@claude-status-stopped-colour' "$4"
}

apply_theme() {
    local theme="$1"
    local flavor

    if [ "$theme" = catppuccin ]; then
        flavor="$(tmux show-option -gqv '@catppuccin_flavor')"
        theme="catppuccin-${flavor:-mocha}"
    fi

    case "$theme" in
        catppuccin-latte)
            set_colour_options '#40a02b' '#df8e1d' '#d20f39' '#7c7f93'
            ;;
        catppuccin-frappe)
            set_colour_options '#a6d189' '#e5c890' '#e78284' '#949cbb'
            ;;
        catppuccin-macchiato)
            set_colour_options '#a6da95' '#eed49f' '#ed8796' '#939ab7'
            ;;
        catppuccin-mocha)
            set_colour_options '#a6e3a1' '#f9e2af' '#f38ba8' '#9399b2'
            ;;
        custom)
            set_default_option '@claude-status-working-colour' 'colour40'
            set_default_option '@claude-status-waiting-colour' '#ffff00'
            set_default_option '@claude-status-error-colour' 'colour196'
            set_default_option '@claude-status-stopped-colour' 'colour244'
            ;;
        *)
            tmux display-message \
                "claude-tmux-status: unknown theme '$theme'; using custom colours"
            set_default_option '@claude-status-working-colour' 'colour40'
            set_default_option '@claude-status-waiting-colour' '#ffff00'
            set_default_option '@claude-status-error-colour' 'colour196'
            set_default_option '@claude-status-stopped-colour' 'colour244'
            ;;
    esac
}

append_format_marker() {
    local option="$1"
    local value

    value="$(tmux show-option -gv "$option")"
    case "$value" in
        *"$FORMAT_MARKER"*) ;;
        *) tmux set-option -gq "$option" "$value $FORMAT_MARKER" ;;
    esac
}

set_default_option '@claude-status-icon' '●'
set_default_option '@claude-status-theme' 'custom'
apply_theme "$(tmux show-option -gqv '@claude-status-theme')"
set_default_option '@claude-status-auto-contrast' 'on'
set_default_option '@claude-status-show-stopped' 'off'
set_default_option '@claude-tmux-status-generation' '0'

tmux set-option -gq '@claude-tmux-status' \
    "#('$CURRENT_DIR/scripts/render-status.sh' '#{window_id}' '#{@claude-tmux-status-generation}')"

append_format_marker 'window-status-format'
append_format_marker 'window-status-current-format'

if command -v node >/dev/null 2>&1; then
    if ! node "$CURRENT_DIR/scripts/configure-hooks.js" install \
        "$CURRENT_DIR/scripts/claude-hook.sh"; then
        tmux display-message 'claude-tmux-status: failed to install Claude hooks'
    fi
else
    tmux display-message 'claude-tmux-status: node is required to install Claude hooks'
fi

tmux refresh-client -S >/dev/null 2>&1 || true
