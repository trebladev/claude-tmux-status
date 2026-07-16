#!/bin/sh

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

"$ROOT/tests/test-hook.sh"
"$ROOT/tests/test-render.sh"
"$ROOT/tests/test-configure-hooks.sh"
"$ROOT/tests/test-theme-presets.sh"
"$ROOT/tests/test-catppuccin-integration.sh"
"$ROOT/tests/test-tmux-integration.sh"

printf '%s\n' 'all tests: ok'
