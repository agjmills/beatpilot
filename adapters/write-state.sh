#!/bin/bash
# Beatpilot core state writer — the shared building block for all adapters.
# Usage:
#   write-state.sh <energy> [content]   hash content into key/scale/seed
#   write-state.sh <energy> -           read the content from stdin (no argv limits)
#   write-state.sh <energy> --keep      change energy only; keep the current tune
#
#   energy: 0-3 (0=silent, 1=calm, 2=active, 3=intense)
#
# Musical identity (key/scale/seed) should change only when the *task* changes
# (a new prompt); tool calls should use --keep so the piece can develop. The
# engines also hold a new tune back until the next 16-bar phrase boundary.
#
# Auto-starts the ChucK engine if not already running.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib/paths.sh
. "$SCRIPT_DIR/lib/paths.sh" || exit 1

[ -f "$BP_DISABLED" ] && { [ "${2:-}" = "-" ] && cat >/dev/null; exit 0; }

energy="${1:-1}"
case "$energy" in ''|*[!0-9]*) energy=1 ;; esac
[ "$energy" -gt 3 ] && energy=3

if ! command -v chuck &>/dev/null; then
    echo "Beatpilot: ChucK not installed. brew install chuck (macOS) or sudo apt install chuck (Linux)" >&2
    exit 1
fi

# --- Ensure engine is running ---
if [ ! -f "$BP_PID" ] || ! kill -0 "$(cat "$BP_PID")" 2>/dev/null; then
    "${SCRIPT_DIR}/start.sh" >/dev/null 2>&1
    sleep 0.3
fi

hash_of() {
    { md5 -q 2>/dev/null || md5sum 2>/dev/null; } | tr -d ' -' | cut -c1-8
}

key=""; scale_type=""; seed=""
if [ "${2:-}" = "--keep" ] && [ -f "$BP_STATE" ]; then
    { read -r _; read -r key; read -r scale_type; read -r seed; } < "$BP_STATE"
fi
if [ -z "$seed" ]; then
    if [ "${2:-}" = "-" ]; then
        hash_hex=$(hash_of)
    elif [ "${2:-}" = "--keep" ]; then
        hash_hex=$(printf '%s' "$PWD" | hash_of)   # no tune yet: the project's
    else
        hash_hex=$(printf '%s' "${2:-beat}" | hash_of)
    fi
    hash_int=$(printf '%d' "0x${hash_hex:-0}" 2>/dev/null || echo 0)
    key=$(( hash_int % 12 ))
    scale_type=$(( (hash_int / 12) % 4 ))
    seed=$(( (hash_int / 48) % 256 ))
fi
# Engines only compare timestamps for change; add sub-second noise so two
# writes in the same second both count.
ts="$(date +%s)$(printf '%03d' $((RANDOM % 1000)))"

# --- Write state atomically ---
tmp="${BP_STATE}.$$"
printf '%d\n%d\n%d\n%d\n%d\n' "$energy" "$key" "$scale_type" "$seed" "$ts" > "$tmp"
mv -f "$tmp" "$BP_STATE"
