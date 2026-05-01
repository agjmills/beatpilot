#!/bin/bash
# Stop the Beatpilot engine
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
PID_FILE="/tmp/beatpilot.pid"
ENGINE_PATTERN="chuck .*${SCRIPT_DIR}/genres/.*\\.ck"

# Kill by PID file
if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
fi

# Kill any leftover chuck instances from THIS clone only.
# Other ChucK processes (other projects, other clones) are left alone.
pkill -f "$ENGINE_PATTERN" 2>/dev/null

rm -f /tmp/beatpilot-state
echo "Beatpilot stopped"
