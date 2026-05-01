#!/bin/bash
# Start the Beatpilot engine
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
PID_FILE="/tmp/beatpilot.pid"
LOCK_DIR="/tmp/beatpilot.lock"
GENRE_FILE="/tmp/beatpilot-genre"

# Pattern that matches *our* chuck processes (this clone's genres/*.ck path).
# Other ChucK projects on the same machine, or other beatpilot clones, won't match.
ENGINE_PATTERN="chuck .*${SCRIPT_DIR}/genres/.*\\.ck"

# Acquire lock — mkdir is atomic on POSIX, so two concurrent start.sh
# invocations can't both pass this check. Trap clears the lock on exit.
acquired=0
for _ in 1 2 3 4 5; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        acquired=1
        break
    fi
    sleep 0.2
done
if [ "$acquired" -ne 1 ]; then
    echo "Beatpilot: another start in progress (could not acquire $LOCK_DIR)"
    exit 1
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# If a recorded PID is still alive AND it's actually one of ours, do nothing.
if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null && pgrep -f "$ENGINE_PATTERN" | grep -qx "$pid"; then
        echo "Beatpilot already running (PID $pid)"
        exit 0
    fi
fi

# Clean up stale state: kill leftover chuck instances from THIS clone only,
# leaving unrelated chuck processes (other projects, other clones) alone.
pkill -f "$ENGINE_PATTERN" 2>/dev/null
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
new_pid=$!
echo "$new_pid" > "$PID_FILE"
echo "Beatpilot started [${genre}] (PID $new_pid)"

# Sanity check: after a brief settle, exactly one of our chucks should be running.
sleep 0.2
running=$(pgrep -f "$ENGINE_PATTERN" | wc -l | tr -d ' ')
if [ "$running" -gt 1 ]; then
    echo "Warning: $running Beatpilot engines detected — cleaning up extras"
    for pid in $(pgrep -f "$ENGINE_PATTERN"); do
        [ "$pid" != "$new_pid" ] && kill "$pid" 2>/dev/null
    done
fi
