#!/bin/sh

window_target=${1:-}
[ -n "$window_target" ] || exit 0
embedded=${3:-off}

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

style_colour() {
    style_value=$1
    style_key=$2
    style_result=
    saved_ifs=$IFS
    IFS=,
    for style_item in $style_value; do
        case "$style_item" in
            "$style_key"=*) style_result=${style_item#*=} ;;
        esac
    done
    IFS=$saved_ifs
    printf '%s' "$style_result"
}

cube_component() {
    case "$1" in
        0) printf '0' ;;
        1) printf '95' ;;
        2) printf '135' ;;
        3) printf '175' ;;
        4) printf '215' ;;
        5) printf '255' ;;
    esac
}

colour_rgb() {
    colour_value=$1
    case "$colour_value" in
        \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
            colour_hex=${colour_value#\#}
            colour_red=${colour_hex%????}
            colour_rest=${colour_hex#??}
            colour_green=${colour_rest%??}
            colour_blue=${colour_rest#??}
            printf '%d %d %d' \
                "$(printf '%d' "0x$colour_red")" \
                "$(printf '%d' "0x$colour_green")" \
                "$(printf '%d' "0x$colour_blue")"
            return 0
            ;;
        black) printf '0 0 0'; return 0 ;;
        red) printf '205 0 0'; return 0 ;;
        green) printf '0 205 0'; return 0 ;;
        yellow) printf '205 205 0'; return 0 ;;
        blue) printf '0 0 238'; return 0 ;;
        magenta) printf '205 0 205'; return 0 ;;
        cyan) printf '0 205 205'; return 0 ;;
        white) printf '229 229 229'; return 0 ;;
        brightblack) printf '127 127 127'; return 0 ;;
        brightred) printf '255 0 0'; return 0 ;;
        brightgreen) printf '0 255 0'; return 0 ;;
        brightyellow) printf '255 255 0'; return 0 ;;
        brightblue) printf '92 92 255'; return 0 ;;
        brightmagenta) printf '255 0 255'; return 0 ;;
        brightcyan) printf '0 255 255'; return 0 ;;
        brightwhite) printf '255 255 255'; return 0 ;;
        colour*|color*)
            colour_number=${colour_value#colour}
            colour_number=${colour_number#color}
            case "$colour_number" in
                ''|*[!0-9]*) return 1 ;;
            esac
            [ "$colour_number" -le 255 ] || return 1
            case "$colour_number" in
                0) printf '0 0 0'; return 0 ;;
                1) printf '205 0 0'; return 0 ;;
                2) printf '0 205 0'; return 0 ;;
                3) printf '205 205 0'; return 0 ;;
                4) printf '0 0 238'; return 0 ;;
                5) printf '205 0 205'; return 0 ;;
                6) printf '0 205 205'; return 0 ;;
                7) printf '229 229 229'; return 0 ;;
                8) printf '127 127 127'; return 0 ;;
                9) printf '255 0 0'; return 0 ;;
                10) printf '0 255 0'; return 0 ;;
                11) printf '255 255 0'; return 0 ;;
                12) printf '92 92 255'; return 0 ;;
                13) printf '255 0 255'; return 0 ;;
                14) printf '0 255 255'; return 0 ;;
                15) printf '255 255 255'; return 0 ;;
            esac
            if [ "$colour_number" -le 231 ]; then
                colour_index=$((colour_number - 16))
                colour_red=$(cube_component $((colour_index / 36)))
                colour_green=$(cube_component $(((colour_index % 36) / 6)))
                colour_blue=$(cube_component $((colour_index % 6)))
                printf '%s %s %s' "$colour_red" "$colour_green" "$colour_blue"
            else
                colour_gray=$((8 + (colour_number - 232) * 10))
                printf '%s %s %s' "$colour_gray" "$colour_gray" "$colour_gray"
            fi
            return 0
            ;;
    esac
    return 1
}

colours_close() {
    close_red=$(( $1 - $4 ))
    close_green=$(( $2 - $5 ))
    close_blue=$(( $3 - $6 ))
    close_distance=$((close_red * close_red + close_green * close_green + close_blue * close_blue))
    [ "$close_distance" -le 6400 ]
}

contrasting_colour() {
    requested_colour=$1

    if [ "$(tmux_option '@claude-status-auto-contrast' 'on')" = off ]; then
        printf '%s' "$requested_colour"
        return
    fi

    contrast_style=$(tmux_option 'status-style' '')
    contrast_background=$(style_colour "$contrast_style" bg)
    contrast_foreground=$(style_colour "$contrast_style" fg)
    case ",$contrast_style," in
        *,reverse,*)
            contrast_swap=$contrast_background
            contrast_background=$contrast_foreground
            contrast_foreground=$contrast_swap
            ;;
    esac

    case "$contrast_background" in
        ''|default)
            printf '%s' "$requested_colour"
            return
            ;;
    esac

    requested_rgb=$(colour_rgb "$requested_colour") || {
        printf '%s' "$requested_colour"
        return
    }
    background_rgb=$(colour_rgb "$contrast_background") || {
        printf '%s' "$requested_colour"
        return
    }
    set -- $requested_rgb $background_rgb
    if ! colours_close "$@"; then
        printf '%s' "$requested_colour"
        return
    fi

    foreground_rgb=$(colour_rgb "$contrast_foreground") || foreground_rgb=
    if [ -n "$foreground_rgb" ]; then
        set -- $foreground_rgb $background_rgb
        if ! colours_close "$@"; then
            printf '%s' "$contrast_foreground"
            return
        fi
    fi

    set -- $background_rgb
    contrast_luma=$((299 * $1 + 587 * $2 + 114 * $3))
    if [ "$contrast_luma" -ge 128000 ]; then
        printf '#000000'
    else
        printf '#ffffff'
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
    [ "$(tmux_option '@claude-status-show-stopped' 'off')" = off ]; then
    exit 0
fi

icon=$(tmux_option '@claude-status-icon' '●')
case "$best_state" in
    working) colour=$(tmux_option '@claude-status-working-colour' 'colour40') ;;
    waiting) colour=$(tmux_option '@claude-status-waiting-colour' '#ffff00') ;;
    error) colour=$(tmux_option '@claude-status-error-colour' 'colour196') ;;
    stopped) colour=$(tmux_option '@claude-status-stopped-colour' 'colour244') ;;
esac

colour=$(contrasting_colour "$colour")

if [ "$embedded" = on ]; then
    printf ' #[fg=%s]%s ' "$colour" "$icon"
else
    printf '#[fg=%s]%s#[default]' "$colour" "$icon"
fi
