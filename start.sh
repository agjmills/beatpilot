#!/bin/bash
# Start the Beatpilot engine
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
PID_FILE="/tmp/beatpilot.pid"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Beatpilot already running (PID $(cat "$PID_FILE"))"
    exit 0
fi

# Clear old state
rm -f /tmp/beatpilot-state

chuck "${SCRIPT_DIR}/engine.ck" &
echo $! > "$PID_FILE"
echo "Beatpilot started (PID $!)"
