#!/bin/sh

window_target=${1:-}
[ -n "$window_target" ] || exit 0

uid=$(id -u)
state_dir=${CLAUDE_TMUX_STATUS_DIR:-/tmp/claude-tmux-status-$uid}

tmux_option() {
    value=$(tmux show-option -gqv "$1" 2>/dev/null)
    if [ -n "$value" ]; then
        printf '%s' "$value"
    else
        printf '%s' "$2"
    fi
}

best_state=
best_priority=0

panes=$(tmux list-panes -t "$window_target" -F '#{pane_id}|#{pane_pid}' 2>/dev/null) || exit 0
old_ifs=$IFS
IFS='
'
for pane in $panes; do
    pane_id=${pane%%|*}
    current_pane_pid=${pane#*|}
    pane_key=${pane_id#%}
    state_file=$state_dir/pane-$pane_key

    [ -r "$state_file" ] || continue

    state=
    updated=
    claude_pid=
    recorded_pane_pid=
    tab=$(printf '\t')
    IFS="$tab" read -r state updated claude_pid recorded_pane_pid <"$state_file"
    IFS='
'

    # A pane id can be reused after a tmux server restart. Ignore an old file
    # unless it belongs to the pane's current shell process.
    [ "$recorded_pane_pid" = "$current_pane_pid" ] || continue

    case "$state" in
        working|waiting|error)
            case "$claude_pid" in
                ''|*[!0-9]*) state=stopped ;;
                *) kill -0 "$claude_pid" 2>/dev/null || state=stopped ;;
            esac
            ;;
        stopped) ;;
        *) continue ;;
    esac

    case "$state" in
        error) priority=4 ;;
        waiting) priority=3 ;;
        working) priority=2 ;;
        stopped) priority=1 ;;
    esac

    if [ "$priority" -gt "$best_priority" ]; then
        best_priority=$priority
        best_state=$state
    fi
done
IFS=$old_ifs

[ -n "$best_state" ] || exit 0

if [ "$best_state" = stopped ] && \
    [ "$(tmux_option '@claude-status-show-stopped' 'on')" = off ]; then
    exit 0
fi

icon=$(tmux_option '@claude-status-icon' '●')
case "$best_state" in
    working) colour=$(tmux_option '@claude-status-working-colour' 'colour40') ;;
    waiting) colour=$(tmux_option '@claude-status-waiting-colour' '#ffff00') ;;
    error) colour=$(tmux_option '@claude-status-error-colour' 'colour196') ;;
    stopped) colour=$(tmux_option '@claude-status-stopped-colour' 'colour244') ;;
esac

printf '#[fg=%s]%s#[default]' "$colour" "$icon"
