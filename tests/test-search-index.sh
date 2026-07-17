#!/bin/sh

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/config/projects/demo" "$TEST_DIR/state"

printf '%s\n' \
    '#!/bin/sh' \
    'case "$1" in' \
    '  list-panes) printf "%b" "$FAKE_PANES" ;;' \
    '  switch-client|select-window|select-pane) printf "%s\n" "$*" >>"$TMUX_LOG" ;;' \
    '  *) exit 1 ;;' \
    'esac' >"$TEST_DIR/bin/tmux"
chmod +x "$TEST_DIR/bin/tmux"

transcript="$TEST_DIR/config/projects/demo/session-123.jsonl"
printf '%s\n' \
    '{"type":"ai-title","aiTitle":"Search feature"}' \
    '{"type":"user","message":{"content":"needle from user"},"isMeta":false}' \
    '{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"private thought"}]}}' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"needle from assistant"}]}}' \
    '{"type":"system","tool_input":{"command":"must-not-be-indexed"}}' \
    >"$transcript"

printf 'waiting\t1\t1111\t4242\n' >"$TEST_DIR/state/pane-7"
printf '{"sessionId":"session-123","transcriptPath":"%s","cwd":"/work","updated":1,"claudePid":1111,"panePid":4242}\n' \
    "$transcript" >"$TEST_DIR/state/pane-7.meta"

output=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='$1\tmain\t@1\t2\teditor\t%7\t0\t1\t4242\t/work\n' \
    CLAUDE_CONFIG_DIR="$TEST_DIR/config" \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    node "$ROOT/scripts/search-index.js")

printf '%s\n' "$output" | grep -F 'main:2  editor  /work' >/dev/null
printf '%s\n' "$output" | grep -F 'needle from user' >/dev/null
printf '%s\n' "$output" | grep -F 'needle from assistant' >/dev/null
case "$output" in
    *private\ thought*|*must-not-be-indexed*) exit 1 ;;
esac

# A reused pane id must not expose chat history from its previous process.
stale=$(PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='$1\tmain\t@1\t2\teditor\t%7\t0\t1\t9999\t/work\n' \
    CLAUDE_CONFIG_DIR="$TEST_DIR/config" \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    node "$ROOT/scripts/search-index.js")
case "$stale" in *needle*) exit 1 ;; esac

# The popup's selected row must switch session, window, and pane in order.
printf '%s\n' \
    '#!/bin/sh' \
    'printf "%s\n" "$*" >"$FZF_ARGS_LOG"' \
    'first=' \
    'while IFS= read -r line; do [ -n "$first" ] || first=$line; done' \
    'printf "%s\n" "$first" >"$CLAUDE_TMUX_SELECTION_FILE"' >"$TEST_DIR/bin/fzf"
chmod +x "$TEST_DIR/bin/fzf"


log="$TEST_DIR/tmux.log"
fzf_args_log="$TEST_DIR/fzf-args.log"
: >"$log"
PATH="$TEST_DIR/bin:$PATH" \
    FAKE_PANES='$1\tmain\t@1\t2\teditor\t%7\t0\t1\t4242\t/work\n' \
    CLAUDE_CONFIG_DIR="$TEST_DIR/config" \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    FZF_ARGS_LOG="$fzf_args_log" \
    TMUX_LOG="$log" \
    "$ROOT/scripts/search-popup.sh"

grep -F 'up:up,down:down,left:backward-char,right:forward-char' "$fzf_args_log" >/dev/null
grep -F 'enter:execute-silent(' "$fzf_args_log" >/dev/null
grep -F -- '--preview=case {1} in chat)' "$fzf_args_log" >/dev/null
grep -F -- '--preview-window=right,55%,border-left,wrap,follow' "$fzf_args_log" >/dev/null
grep -F -- '--color=fg:#c6d0f5,bg:#303446' "$fzf_args_log" >/dev/null
grep -F -- '--border=none' "$fzf_args_log" >/dev/null
if grep -F 'esc:' "$fzf_args_log" >/dev/null; then
    exit 1
fi

expected='switch-client -t $1
select-window -t @1
select-pane -t %7'
[ "$(cat "$log")" = "$expected" ]

printf '%s\n' 'test-search-index: ok'
