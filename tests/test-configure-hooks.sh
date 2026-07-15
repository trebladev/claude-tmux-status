#!/bin/sh

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

mkdir -p "$TEST_DIR/config"
printf '%s\n' '{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/custom/hook"}]}]}}' \
    >"$TEST_DIR/config/settings.json"

CLAUDE_CONFIG_DIR="$TEST_DIR/config" \
    node "$ROOT/scripts/configure-hooks.js" install "$ROOT/scripts/claude-hook.sh"

node -e '
const s = require(process.argv[1]);
if (s.theme !== "dark") process.exit(1);
if (!s.hooks.Stop.some(g => g.hooks.some(h => h.command === "/custom/hook"))) process.exit(1);
const ours = Object.values(s.hooks).flat().flatMap(g => g.hooks || [])
  .filter(h => (h.args || []).includes("claude-tmux-status-v1"));
if (ours.length !== 8) process.exit(1);
' "$TEST_DIR/config/settings.json"

before=$(cksum "$TEST_DIR/config/settings.json")
CLAUDE_CONFIG_DIR="$TEST_DIR/config" \
    node "$ROOT/scripts/configure-hooks.js" install "$ROOT/scripts/claude-hook.sh"
after=$(cksum "$TEST_DIR/config/settings.json")
[ "$before" = "$after" ]

CLAUDE_CONFIG_DIR="$TEST_DIR/config" \
    node "$ROOT/scripts/configure-hooks.js" uninstall

node -e '
const s = require(process.argv[1]);
if (!s.hooks.Stop.some(g => g.hooks.some(h => h.command === "/custom/hook"))) process.exit(1);
const ours = Object.values(s.hooks).flat().flatMap(g => g.hooks || [])
  .filter(h => (h.args || []).includes("claude-tmux-status-v1"));
if (ours.length !== 0) process.exit(1);
' "$TEST_DIR/config/settings.json"

printf '%s\n' 'test-configure-hooks: ok'

