#!/bin/bash
# Beatpilot core state writer — the shared building block for all adapters.
# Usage: write-state.sh <energy> [content]
#   energy:  0-3 (0=silent, 1=calm, 2=active, 3=intense)
#   content: any string — gets hashed into key, scale, and seed for musical variation
#
# Auto-starts the ChucK engine if not already running.
# Writes /tmp/beatpilot-state atomically.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="/tmp/beatpilot.pid"
STATE_FILE="/tmp/beatpilot-state"

# --- Check if disabled ---
[ -f /tmp/beatpilot-disabled ] && exit 0

# --- Validate args ---
energy="${1:-1}"
content="${2:-beat}"

# Clamp energy 0-3
[ "$energy" -gt 3 ] 2>/dev/null && energy=3
[ "$energy" -lt 0 ] 2>/dev/null && energy=0

# --- Check dependencies ---
if ! command -v chuck &>/dev/null; then
    echo "Beatpilot: ChucK not installed. brew install chuck (macOS) or sudo apt install chuck (Linux)" >&2
    exit 1
fi

# --- Ensure engine is running ---
if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    "${SCRIPT_DIR}/start.sh" >/dev/null 2>&1
    sleep 0.3
fi

# --- Hash content for musical variation ---
hash_hex=$(echo -n "$content" | md5 -q 2>/dev/null || echo -n "$content" | md5sum 2>/dev/null | cut -c1-8)
hash_hex=$(echo "$hash_hex" | tr -d ' -' | cut -c1-8)
hash_int=$(printf '%d' "0x${hash_hex}" 2>/dev/null || echo 0)

key=$(( hash_int % 12 ))
scale_type=$(( (hash_int / 12) % 4 ))
seed=$(( (hash_int / 48) % 256 ))
ts=$(date +%s)

# --- Write state atomically ---
tmp="${STATE_FILE}.$$"
printf '%d\n%d\n%d\n%d\n%d\n' "$energy" "$key" "$scale_type" "$seed" "$ts" > "$tmp"
mv -f "$tmp" "$STATE_FILE"
