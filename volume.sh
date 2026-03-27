#!/bin/bash
# Set Beatpilot volume (0-100)
VOLUME_FILE="/tmp/beatpilot-volume"

vol="$1"

if [ -z "$vol" ]; then
    current="80"
    [ -f "$VOLUME_FILE" ] && current=$(cat "$VOLUME_FILE")
    echo "Volume: ${current}%"
    exit 0
fi

if [ "$vol" -lt 0 ] 2>/dev/null || [ "$vol" -gt 100 ] 2>/dev/null; then
    echo "Volume must be 0-100"
    exit 1
fi

echo "$vol" > "$VOLUME_FILE"
echo "Volume: ${vol}%"
