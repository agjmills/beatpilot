#!/bin/bash
# Stop the Beatpilot engine
PID_FILE="/tmp/beatpilot.pid"

# Kill by PID file
if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
fi

# Kill any remaining engine processes
pkill -f "chuck.*engine.ck" 2>/dev/null

rm -f /tmp/beatpilot-state
echo "Beatpilot stopped"
