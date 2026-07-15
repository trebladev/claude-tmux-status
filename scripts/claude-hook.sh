#!/bin/sh

# Claude Code invokes this script in exec form, so PPID is the Claude process.
# The JSON event on stdin is intentionally discarded: no prompt or transcript
# content is stored.

state=${1:-}

case "$state" in
    working|waiting|error|stopped) ;;
    *) exit 0 ;;
esac

# Drain Claude's JSON input so large tool payloads cannot hit a closed pipe.
# Its contents are never parsed or persisted.
cat >/dev/null 2>&1 || true

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

pane_pid=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_pid}' 2>/dev/null) || exit 0
case "$pane_pid" in
    ''|*[!0-9]*) exit 0 ;;
esac

uid=$(id -u)
state_dir=${CLAUDE_TMUX_STATUS_DIR:-/tmp/claude-tmux-status-$uid}
pane_key=${TMUX_PANE#%}
state_file=$state_dir/pane-$pane_key
tmp_file=$state_file.$$

umask 077
mkdir -p "$state_dir" || exit 0

# /tmp is shared. Refuse a directory pre-created by a different user, then
# enforce private permissions before creating predictable pane filenames.
dir_owner=$(stat -c '%u' "$state_dir" 2>/dev/null || stat -f '%u' "$state_dir" 2>/dev/null) || exit 0
[ "$dir_owner" = "$uid" ] || exit 0
chmod 700 "$state_dir" 2>/dev/null || exit 0

trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

# state, update epoch, Claude PID, and tmux pane's original shell PID.
printf '%s\t%s\t%s\t%s\n' \
    "$state" "$(date +%s)" "$PPID" "$pane_pid" >"$tmp_file" || exit 0
mv "$tmp_file" "$state_file" || exit 0
trap - EXIT HUP INT TERM

# tmux caches #() jobs by their expanded command. A unique generation changes
# the command key on every event, so very fast turns cannot retain an older
# colour until the next status-interval tick.
tmux set-option -gq '@claude-tmux-status-generation' "$$" >/dev/null 2>&1 || true

# Hooks should never delay Claude. Refresh is best-effort and normally instant.
tmux refresh-client -S >/dev/null 2>&1 || true
exit 0
