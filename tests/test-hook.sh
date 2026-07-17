#!/bin/sh

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/state"

printf '%s\n' \
    '#!/bin/sh' \
    'case "$1" in' \
    '  display-message) printf "%s\n" "${FAKE_PANE_PID:-4242}" ;;' \
    '  refresh-client) exit 0 ;;' \
    '  *) exit 1 ;;' \
    'esac' >"$TEST_DIR/bin/tmux"
chmod +x "$TEST_DIR/bin/tmux"

PATH="$TEST_DIR/bin:$PATH" \
TMUX_PANE='%7' \
FAKE_PANE_PID=4242 \
CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/claude-hook.sh" working </dev/null

state_file="$TEST_DIR/state/pane-7"
[ -f "$state_file" ]

tab=$(printf '\t')
IFS="$tab" read -r state updated claude_pid pane_pid <"$state_file"
[ "$state" = working ]
[ "$pane_pid" = 4242 ]
case "$updated:$claude_pid" in
    *[!0-9:]*|:*|*:) exit 1 ;;
esac
# A valid hook payload stores only the pane-to-transcript mapping.
payload='{"session_id":"session-123","transcript_path":"/tmp/project/session-123.jsonl","cwd":"/tmp/project","prompt":"must-not-be-stored"}'
printf '%s' "$payload" | \
    PATH="$TEST_DIR/bin:$PATH" \
    TMUX_PANE='%7' \
    FAKE_PANE_PID=4242 \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/claude-hook.sh" waiting

meta_file="$TEST_DIR/state/pane-7.meta"
[ -f "$meta_file" ]
node -e '
const fs = require("fs");
const metadata = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (metadata.sessionId !== "session-123") process.exit(1);
if (metadata.transcriptPath !== "/tmp/project/session-123.jsonl") process.exit(1);
if (metadata.cwd !== "/tmp/project") process.exit(1);
if (JSON.stringify(metadata).includes("must-not-be-stored")) process.exit(1);
' "$meta_file"

# Subagent hooks must not overwrite the main agent's state or transcript map.
state_before=$(cat "$state_file")
meta_before=$(cat "$meta_file")
subagent_payload='{"session_id":"session-subagent","transcript_path":"/tmp/project/subagent.jsonl","cwd":"/tmp/project","agent_id":"agent-123","agent_type":"Explore"}'
printf '%s' "$subagent_payload" | \
    PATH="$TEST_DIR/bin:$PATH" \
    TMUX_PANE='%7' \
    FAKE_PANE_PID=4242 \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/claude-hook.sh" error
[ "$(cat "$state_file")" = "$state_before" ]
[ "$(cat "$meta_file")" = "$meta_before" ]


# A hook outside tmux must be a harmless no-op.
env -u TMUX_PANE \
    PATH="$TEST_DIR/bin:$PATH" \
    CLAUDE_TMUX_STATUS_DIR="$TEST_DIR/state" \
    "$ROOT/scripts/claude-hook.sh" error </dev/null

printf '%s\n' 'test-hook: ok'
