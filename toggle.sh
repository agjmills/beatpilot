#!/bin/bash
# Toggle Beatpilot on/off
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
PID_FILE="/tmp/beatpilot.pid"
DISABLED_FILE="/tmp/beatpilot-disabled"

if [ -f "$DISABLED_FILE" ]; then
    # Currently disabled — enable and start
    rm -f "$DISABLED_FILE"
    "${SCRIPT_DIR}/start.sh"
    echo "Beatpilot: ON"
else
    # Currently enabled — stop and disable
    "${SCRIPT_DIR}/stop.sh" >/dev/null 2>&1
    touch "$DISABLED_FILE"
    echo "Beatpilot: OFF"
fi
