#!/bin/sh

set -eu

command -v tmux >/dev/null 2>&1 || {
    printf '%s\n' 'test-tmux-integration: skipped (tmux not installed)'
    exit 0
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
SOCKET=claude-tmux-status-test-$$

cleanup() {
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/config" "$TEST_DIR/state"

CLAUDE_CONFIG_DIR="$TEST_DIR/config" \
CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    tmux -L "$SOCKET" -f /dev/null new-session -d -s status-test
tmux -L "$SOCKET" run-shell "$ROOT/claude-tmux-status.tmux"

marker='#{E:@claude-tmux-status}'
inactive=$(tmux -L "$SOCKET" show-option -gv window-status-format)
active=$(tmux -L "$SOCKET" show-option -gv window-status-current-format)
case "$inactive:$active" in
    *"$marker"*:*"$marker"*) ;;
    *) exit 1 ;;
esac
search_binding=$(tmux -L "$SOCKET" list-keys -T prefix /)
case "$search_binding" in *search-popup.sh*) ;; *) exit 1 ;; esac
case "$search_binding" in *'Claude Search'*'#303446'*) ;; *) exit 1 ;; esac


# Reloading the plugin must not append another marker.
tmux -L "$SOCKET" run-shell "$ROOT/claude-tmux-status.tmux"
inactive=$(tmux -L "$SOCKET" show-option -gv window-status-format)
remainder=${inactive#*"$marker"}
case "$remainder" in
    *"$marker"*) exit 1 ;;
esac

pane_id=$(tmux -L "$SOCKET" display-message -p '#{pane_id}')
window_id=$(tmux -L "$SOCKET" display-message -p '#{window_id}')
pane_key=${pane_id#%}
generation_before=$(tmux -L "$SOCKET" show-option -gqv '@claude-tmux-status-generation')

tmux -L "$SOCKET" send-keys -l "$ROOT/scripts/claude-hook.sh waiting </dev/null"
tmux -L "$SOCKET" send-keys Enter

attempt=0
while [ ! -s "$TEST_DIR/state/pane-$pane_key" ] && [ "$attempt" -lt 40 ]; do
    sleep 0.05
    attempt=$((attempt + 1))
done
[ -s "$TEST_DIR/state/pane-$pane_key" ]
generation_after=$(tmux -L "$SOCKET" show-option -gqv '@claude-tmux-status-generation')
[ -n "$generation_after" ]
[ "$generation_after" != "$generation_before" ]

printf '%s\n' \
    '#!/bin/sh' \
    "exec /usr/bin/tmux -L '$SOCKET' \"\$@\"" >"$TEST_DIR/bin/tmux"
chmod +x "$TEST_DIR/bin/tmux"

output=$(PATH="$TEST_DIR/bin:$PATH" \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/render-status.sh" "$window_id")
[ "$output" = '#[fg=#ffff00]●#[default]' ]

node -e '
const s = require(process.argv[1]);
const ours = Object.values(s.hooks).flat().flatMap(g => g.hooks || [])
  .filter(h => (h.args || []).includes("claude-tmux-status-v1"));
if (ours.length !== 8) process.exit(1);
' "$TEST_DIR/config/settings.json"

printf '%s\n' 'test-tmux-integration: ok'
