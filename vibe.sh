#!/bin/bash
# Switch Beatpilot genre
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
# shellcheck source=lib/paths.sh
. "$SCRIPT_DIR/lib/paths.sh" || exit 1

genre="$1"

if [ -z "$genre" ]; then
    current=$(bp_genre)
    echo "Available vibes:"
    for name in $BEATPILOT_GENRES; do
        if [ "$name" = "$current" ]; then
            echo "  * ${name} (active)"
        else
            echo "    ${name}"
        fi
    done
    exit 0
fi

if ! bp_valid_genre "$genre" || [ ! -f "${SCRIPT_DIR}/genres/${genre}.ck" ]; then
    echo "Unknown vibe: ${genre}"
    echo "Available: ${BEATPILOT_GENRES}"
    exit 1
fi

echo "$genre" > "$BP_GENRE"
"${SCRIPT_DIR}/stop.sh" >/dev/null 2>&1
rm -f "$BP_DISABLED"
"${SCRIPT_DIR}/start.sh"
