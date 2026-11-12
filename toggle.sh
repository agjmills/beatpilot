#!/bin/bash
# Toggle Beatpilot on/off
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
# shellcheck source=lib/paths.sh
. "$SCRIPT_DIR/lib/paths.sh" || exit 1

if [ -f "$BP_DISABLED" ]; then
    rm -f "$BP_DISABLED"
    "${SCRIPT_DIR}/start.sh"
    echo "Beatpilot: ON"
else
    "${SCRIPT_DIR}/stop.sh" >/dev/null 2>&1
    touch "$BP_DISABLED"
    echo "Beatpilot: OFF"
fi
