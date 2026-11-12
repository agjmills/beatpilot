#!/bin/bash
# Start the Beatpilot engine.
#   start.sh               start in the background (shell adapters)
#   start.sh --foreground  replace this process with the engine (the Claude
#                          Code mod owns it this way, so it dies with the session)
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
# shellcheck source=lib/paths.sh
. "$SCRIPT_DIR/lib/paths.sh" || exit 1

foreground=0
[ "${1:-}" = "--foreground" ] && foreground=1

if ! command -v chuck &>/dev/null; then
    echo "Beatpilot: ChucK not installed. brew install chuck (macOS) or sudo apt install chuck (Linux)" >&2
    exit 1
fi

# --- Lock: mkdir is atomic. The lock holds its owner's PID so a lock left by
# a killed start (SIGKILL skips traps) is broken instead of blocking forever.
take_lock() {
    if mkdir "$BP_LOCK" 2>/dev/null; then
        echo $$ > "$BP_LOCK/pid"
        return 0
    fi
    local owner
    owner=$(cat "$BP_LOCK/pid" 2>/dev/null)
    if [ -z "$owner" ] || ! kill -0 "$owner" 2>/dev/null; then
        rm -rf "$BP_LOCK"
        mkdir "$BP_LOCK" 2>/dev/null && echo $$ > "$BP_LOCK/pid" && return 0
    fi
    return 1
}
acquired=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
    take_lock && { acquired=1; break; }
    sleep 0.2
done
if [ "$acquired" -ne 1 ]; then
    echo "Beatpilot: another start in progress"
    exit 1
fi
trap 'rm -rf "$BP_LOCK"' EXIT

# Already running and really ours? Nothing to do.
if [ -f "$BP_PID" ]; then
    pid=$(cat "$BP_PID")
    if kill -0 "$pid" 2>/dev/null && pgrep -f "$BP_ENGINE_PATTERN" | grep -qx "$pid"; then
        echo "Beatpilot already running (PID $pid)"
        exit 0
    fi
fi

# Stale engines of this user from any clone or install: clear them out.
pkill -f "$BP_ENGINE_PATTERN" 2>/dev/null
rm -f "$BP_STATE" "$BP_PID" "$BP_NOW"
sleep 0.1

genre=$(bp_genre)   # validated against the known list: never a path
engine="${SCRIPT_DIR}/genres/${genre}.ck"

# The engine gets the runtime directory as its argument (genre.ck:<dir>).
if [ "$foreground" -eq 1 ]; then
    echo $$ > "$BP_PID"
    rm -rf "$BP_LOCK"
    trap - EXIT
    exec chuck "${engine}:${BEATPILOT_RUN}"
fi

chuck "${engine}:${BEATPILOT_RUN}" >/dev/null 2>&1 &
new_pid=$!
echo "$new_pid" > "$BP_PID"
echo "Beatpilot started [${genre}] (PID $new_pid)"
