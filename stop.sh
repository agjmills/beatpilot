#!/bin/bash
# Stop the Beatpilot engine
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
PID_FILE="/tmp/beatpilot.pid"
# Match any Beatpilot chuck process on this machine (any clone or install).
ENGINE_PATTERN="chuck .*/genres/(techno|dnb|lofi|reggae|dub|goa|piano|ambient)\\.ck"

# Kill by PID file
if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
fi

# Kill any leftover Beatpilot chuck instances anywhere on the machine.
# Non-Beatpilot ChucK processes are left alone.
pkill -f "$ENGINE_PATTERN" 2>/dev/null

rm -f /tmp/beatpilot-state
echo "Beatpilot stopped"
