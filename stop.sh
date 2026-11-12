#!/bin/bash
# Stop the Beatpilot engine
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
# shellcheck source=lib/paths.sh
. "$SCRIPT_DIR/lib/paths.sh" || exit 1

if [ -f "$BP_PID" ]; then
    kill "$(cat "$BP_PID")" 2>/dev/null
    rm -f "$BP_PID"
fi
# Any leftover Beatpilot engine of this user, from any clone or install.
pkill -f "$BP_ENGINE_PATTERN" 2>/dev/null

rm -f "$BP_STATE" "$BP_NOW"
echo "Beatpilot stopped"
