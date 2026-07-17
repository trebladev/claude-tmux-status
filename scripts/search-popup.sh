#!/usr/bin/env bash

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v fzf >/dev/null 2>&1; then
    tmux display-message 'claude-tmux-status: fzf is required for search'
    exit 0
fi
if ! command -v node >/dev/null 2>&1; then
    tmux display-message 'claude-tmux-status: node is required for chat search'
    exit 0
fi

index_file=$(mktemp "${TMPDIR:-/tmp}/claude-tmux-status-index.XXXXXX") || exit 1
selection_file=$(mktemp "${TMPDIR:-/tmp}/claude-tmux-status-search.XXXXXX") || {
    rm -f "$index_file"
    exit 1
}
trap 'rm -f "$index_file" "$selection_file"' EXIT
select_binding='enter:execute-silent(printf "%s\n" {} > "$CLAUDE_TMUX_SELECTION_FILE")+abort'
preview_command='case {1} in chat) printf "%s" {5} | base64 -d 2>/dev/null ;; window) tmux capture-pane -ep -t {4} -S -200 2>/dev/null ;; esac'
fzf_colors='fg:#c6d0f5,bg:#303446,hl:#e5c890,fg+:#c6d0f5,bg+:#414559,hl+:#ef9f76,info:#949cbb,prompt:#8caaee,pointer:#ca9ee6,marker:#a6d189,spinner:#ef9f76,header:#b5bfe2,border:#51576d,label:#8caaee,query:#c6d0f5,gutter:#303446,preview-bg:#292c3c'

node "$CURRENT_DIR/search-index.js" >"$index_file" || exit 0

CLAUDE_TMUX_SELECTION_FILE="$selection_file" fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=6.. \
    --nth=6.. \
    --no-multi \
    --layout=reverse \
    --color="$fzf_colors" \
    --border=none \
    --padding='1,2' \
    --prompt='  ' \
    --pointer='▌' \
    --marker='✓' \
    --info=inline-right \
    --scrollbar='│' \
    --preview="$preview_command" \
    --preview-window='right,55%,border-left,wrap,follow' \
    --bind="$select_binding,up:up,down:down,left:backward-char,right:forward-char" \
    --tiebreak=index <"$index_file" || true

IFS= read -r selection <"$selection_file" || exit 0

IFS=$'\t' read -r kind session_id window_id pane_id _ <<<"$selection"
[ -n "$session_id" ] && [ -n "$window_id" ] && [ -n "$pane_id" ] || exit 0

tmux switch-client -t "$session_id" 2>/dev/null || exit 0
tmux select-window -t "$window_id" 2>/dev/null || exit 0
tmux select-pane -t "$pane_id" 2>/dev/null || true
