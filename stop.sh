#!/bin/bash
# Stop the Beatpilot engine
PID_FILE="/tmp/beatpilot.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        echo "Beatpilot stopped (PID $PID)"
    else
        echo "Beatpilot was not running (stale PID)"
    fi
    rm -f "$PID_FILE" /tmp/beatpilot-state
else
    echo "Beatpilot is not running"
fi
