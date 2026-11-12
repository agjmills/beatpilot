#!/bin/bash
# Beatpilot runtime paths — sourced by every script, and run with --print by
# the Claude Code mod so both agree on one per-user directory.
#
# Everything lives in a private (0700) directory owned by the current user,
# never at fixed names in a shared /tmp:
#   $BEATPILOT_RUN_DIR             explicit override
#   $XDG_RUNTIME_DIR/beatpilot     Linux with systemd (already per-user)
#   $TMPDIR/beatpilot-<uid>        macOS (TMPDIR is per-user) / fallback
#   /tmp/beatpilot-<uid>           last resort, ownership checked

# shellcheck disable=SC2034  # these are read by the scripts that source this file
BEATPILOT_GENRES="techno dnb lofi reggae dub goa piano ambient"

if [ -n "$BEATPILOT_RUN_DIR" ]; then
    BEATPILOT_RUN="$BEATPILOT_RUN_DIR"
elif [ -n "$XDG_RUNTIME_DIR" ] && [ -d "$XDG_RUNTIME_DIR" ]; then
    BEATPILOT_RUN="$XDG_RUNTIME_DIR/beatpilot"
else
    BEATPILOT_RUN="${TMPDIR:-/tmp}"
    BEATPILOT_RUN="${BEATPILOT_RUN%/}/beatpilot-$(id -u)"
fi

if [ ! -d "$BEATPILOT_RUN" ]; then
    (umask 077 && mkdir -p "$BEATPILOT_RUN") || {
        echo "Beatpilot: cannot create $BEATPILOT_RUN" >&2
        return 1 2>/dev/null || exit 1
    }
fi
# Refuse a directory someone else created or can write to.
if [ ! -O "$BEATPILOT_RUN" ] || [ -L "$BEATPILOT_RUN" ]; then
    echo "Beatpilot: $BEATPILOT_RUN is not owned by you; refusing to use it" >&2
    return 1 2>/dev/null || exit 1
fi
chmod 700 "$BEATPILOT_RUN" 2>/dev/null

BP_STATE="$BEATPILOT_RUN/state"
BP_VOLUME="$BEATPILOT_RUN/volume"
BP_GENRE="$BEATPILOT_RUN/genre"
BP_DISABLED="$BEATPILOT_RUN/disabled"
BP_PID="$BEATPILOT_RUN/engine.pid"
BP_LOCK="$BEATPILOT_RUN/start.lock"
BP_NOW="$BEATPILOT_RUN/now"

# Pattern for any Beatpilot chuck process of this user (pkill/pgrep only see
# your own processes unless you are root).
BP_ENGINE_PATTERN="chuck .*/genres/(techno|dnb|lofi|reggae|dub|goa|piano|ambient)\\.ck"

bp_valid_genre() {
    case " $BEATPILOT_GENRES " in *" $1 "*) return 0 ;; esac
    return 1
}

# Current genre: the file if it holds a known name, else techno.
bp_genre() {
    local g=""
    [ -f "$BP_GENRE" ] && g=$(head -c 32 "$BP_GENRE" | tr -dc 'a-z')
    bp_valid_genre "$g" && echo "$g" || echo "techno"
}

if [ "${1:-}" = "--print" ]; then
    printf '%s\n' "$BEATPILOT_RUN"
fi
