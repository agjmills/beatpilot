#!/bin/bash
# Set Beatpilot volume (0-100)
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
# shellcheck source=lib/paths.sh
. "$SCRIPT_DIR/lib/paths.sh" || exit 1

vol="$1"

if [ -z "$vol" ]; then
    current="80"
    [ -f "$BP_VOLUME" ] && current=$(cat "$BP_VOLUME")
    echo "Volume: ${current}%"
    exit 0
fi

case "$vol" in
    ''|*[!0-9]*) echo "Volume must be 0-100"; exit 1 ;;
esac
if [ "$vol" -gt 100 ]; then
    echo "Volume must be 0-100"
    exit 1
fi

echo "$vol" > "$BP_VOLUME"
echo "Volume: ${vol}%"
