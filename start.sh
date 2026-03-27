#!/bin/bash
# Start the Beatpilot engine
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
PID_FILE="/tmp/beatpilot.pid"
GENRE_FILE="/tmp/beatpilot-genre"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Beatpilot already running (PID $(cat "$PID_FILE"))"
    exit 0
fi

# Kill any stray engines first
pkill -f "chuck.*genres.*\\.ck" 2>/dev/null
killall chuck 2>/dev/null
rm -f /tmp/beatpilot-state "$PID_FILE"
sleep 0.1

# Read genre (default: techno)
genre="techno"
if [ -f "$GENRE_FILE" ]; then
    genre=$(cat "$GENRE_FILE")
fi

# Find the engine file
engine="${SCRIPT_DIR}/genres/${genre}.ck"
if [ ! -f "$engine" ]; then
    echo "Unknown genre: ${genre} (falling back to techno)"
    engine="${SCRIPT_DIR}/genres/techno.ck"
fi

chuck "$engine" &
echo $! > "$PID_FILE"
echo "Beatpilot started [${genre}] (PID $!)"
