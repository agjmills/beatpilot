#!/bin/bash
# Switch Beatpilot genre
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
GENRE_FILE="/tmp/beatpilot-genre"
GENRES_DIR="${SCRIPT_DIR}/genres"

genre="$1"

# List available genres if no argument
if [ -z "$genre" ]; then
    current="techno"
    [ -f "$GENRE_FILE" ] && current=$(cat "$GENRE_FILE")
    echo "Available vibes:"
    for f in "${GENRES_DIR}"/*.ck; do
        name=$(basename "$f" .ck)
        if [ "$name" = "$current" ]; then
            echo "  * ${name} (active)"
        else
            echo "    ${name}"
        fi
    done
    exit 0
fi

# Check genre exists
if [ ! -f "${GENRES_DIR}/${genre}.ck" ]; then
    echo "Unknown vibe: ${genre}"
    echo "Available: $(ls "${GENRES_DIR}"/*.ck 2>/dev/null | xargs -I{} basename {} .ck | tr '\n' ' ')"
    exit 1
fi

# Write genre and restart
echo "$genre" > "$GENRE_FILE"
"${SCRIPT_DIR}/stop.sh" >/dev/null 2>&1
rm -f /tmp/beatpilot-disabled
"${SCRIPT_DIR}/start.sh"
