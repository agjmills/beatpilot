#!/bin/bash
# install-samples.sh — Download and install CC0 drum samples for Beatpilot
# These are OPTIONAL. Engines fall back to synthesis when samples/ doesn't exist.
#
# Source: Virtuosity Drums (CC0 1.0 Public Domain)
# https://github.com/sfzinstruments/virtuosity_drums

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAMPLES_DIR="$SCRIPT_DIR/samples"
TMP_DIR="/tmp/beatpilot-samples-$$"

# Check for ffmpeg (needed to convert FLAC → WAV)
if ! command -v ffmpeg &>/dev/null; then
    echo "Error: ffmpeg is required to convert samples."
    echo "  macOS: brew install ffmpeg"
    echo "  Linux: sudo apt install ffmpeg"
    exit 1
fi

echo "Downloading Virtuosity Drums (CC0 — public domain)..."
git clone --depth 1 https://github.com/sfzinstruments/virtuosity_drums.git "$TMP_DIR" 2>&1 | tail -1

VD="$TMP_DIR/Samples"

# Create genre directories
mkdir -p "$SAMPLES_DIR"/{lofi,techno,dnb,dub,ambient,goa,goa/voice}

# Helper: convert FLAC to 16-bit 44.1kHz mono WAV
convert() {
    local src="$1" dst="$2"
    ffmpeg -y -i "$src" -ac 1 -ar 44100 -sample_fmt s16 "$dst" -loglevel error
}

echo "Converting samples..."

# ============ LOFI (lofi mic — warm, dusty, lo-fi character) ============
echo "  lofi..."
convert "$VD/lofi/kick/lofi_kick_snoff_vl3_rr1.flac"       "$SAMPLES_DIR/lofi/kick.wav"
convert "$VD/lofi/snare/lofi_snare_center_vl12.flac"        "$SAMPLES_DIR/lofi/snare.wav"
convert "$VD/lofi/snare/lofi_snare_buzz_vl3.flac"           "$SAMPLES_DIR/lofi/snare_ghost.wav"
convert "$VD/lofi/hh/lofi_hh_closed_vl2_rr1.flac"          "$SAMPLES_DIR/lofi/hat_closed.wav"
convert "$VD/lofi/hh/lofi_hh_open_vl2_rr1.flac"            "$SAMPLES_DIR/lofi/hat_open.wav"
convert "$VD/lofi/ride/lofi_ride_ride_vl2_rr1.flac"         "$SAMPLES_DIR/lofi/ride.wav"
convert "$VD/lofi/crash/lofi_crash_crash_vl1_rr1.flac"      "$SAMPLES_DIR/lofi/crash.wav"

# ============ TECHNO (mid mic — punchy, present, tight) ============
echo "  techno..."
convert "$VD/mid/kick/mid_kick_snoff_vl4_rr1.flac"          "$SAMPLES_DIR/techno/kick.wav"
convert "$VD/mid/snare/mid_snare_rimshot_vl12.flac"          "$SAMPLES_DIR/techno/snare.wav"
convert "$VD/mid/snare/mid_snare_center_vl20.flac"           "$SAMPLES_DIR/techno/clap.wav"
convert "$VD/mid/hh/mid_hh_closed_vl3_rr1.flac"             "$SAMPLES_DIR/techno/hat_closed.wav"
convert "$VD/mid/hh/mid_hh_open_vl3_rr1.flac"               "$SAMPLES_DIR/techno/hat_open.wav"
convert "$VD/mid/ride/mid_ride_bell_vl3_rr1.flac"            "$SAMPLES_DIR/techno/ride.wav"

# ============ DnB (snaremic — cracking, aggressive, close) ============
echo "  dnb..."
convert "$VD/snaremic/kick/snaremic_kick_snoff_vl4_rr1.flac"   "$SAMPLES_DIR/dnb/kick.wav"
convert "$VD/snaremic/snare/snaremic_snare_center_vl24.flac"    "$SAMPLES_DIR/dnb/snare.wav"
convert "$VD/snaremic/snare/snaremic_snare_center_vl6.flac"     "$SAMPLES_DIR/dnb/snare_ghost.wav"
convert "$VD/mid/hh/mid_hh_34_vl3_rr1.flac"                    "$SAMPLES_DIR/dnb/hat_closed.wav"
convert "$VD/mid/hh/mid_hh_open_vl3_rr1.flac"                  "$SAMPLES_DIR/dnb/hat_open.wav"
convert "$VD/mid/crash/mid_crash_crash_vl2_rr1.flac"            "$SAMPLES_DIR/dnb/crash.wav"

# ============ DUB (room mic — deep, spacious, reverberant) ============
echo "  dub..."
convert "$VD/room/kick/room_kick_snoff_vl3_rr1.flac"           "$SAMPLES_DIR/dub/kick.wav"
convert "$VD/room/snareoff/room_snareoff_crossstick_vl5.flac"   "$SAMPLES_DIR/dub/rimshot.wav"
convert "$VD/room/snare/room_snare_center_vl12.flac"            "$SAMPLES_DIR/dub/snare.wav"
convert "$VD/room/hh/room_hh_closed_vl2_rr1.flac"              "$SAMPLES_DIR/dub/hat_closed.wav"
convert "$VD/room/hh/room_hh_open_vl2_rr1.flac"                "$SAMPLES_DIR/dub/hat_open.wav"
# Percussion (already WAV in the source)
cp "$VD/perc/close/shaker/LShaker_Shake1D_rr1_Close.wav"       "$SAMPLES_DIR/dub/shaker.wav"
cp "$VD/perc/close/cowbell/Cowbell1_Normal_v1_rr1_Close.wav"    "$SAMPLES_DIR/dub/cowbell.wav"
cp "$VD/perc/close/tambourine/Tamb1_Shake_rr1_Close.wav"       "$SAMPLES_DIR/dub/tambourine.wav"

# ============ GOA (mid mic — punchy 4/4 like techno) ============
echo "  goa..."
convert "$VD/mid/kick/mid_kick_snoff_vl4_rr1.flac"           "$SAMPLES_DIR/goa/kick.wav"
convert "$VD/mid/hh/mid_hh_closed_vl3_rr1.flac"              "$SAMPLES_DIR/goa/hat_closed.wav"
convert "$VD/mid/hh/mid_hh_open_vl3_rr1.flac"                "$SAMPLES_DIR/goa/hat_open.wav"
convert "$VD/mid/snare/mid_snare_center_vl20.flac"           "$SAMPLES_DIR/goa/clap.wav"

# Voice samples directory: README explains how to populate
cat > "$SAMPLES_DIR/goa/voice/README.md" << 'VOICEEOF'
# Goa Voice Samples

The goa engine plays voice clips at phrase boundaries and breakdowns — the classic
psy-trance "spoken word over filter sweep" thing. Drop up to 8 short WAV files
here named `voice_1.wav` through `voice_8.wav`.

## What works well
- 1–4 second clips (anything longer competes with the music)
- Mono, 44.1kHz, 16-bit (any format ChucK reads will work, but this is ideal)
- Voice + room tone is fine — it'll route through the lead delay anyway

## Where to source clips (public domain / fair use)

**Archive.org has plenty:**
- NASA Apollo mission audio: archive.org/details/nasaaudiocollection
- Public domain sci-fi radio (X Minus One, Dimension X)
- Old computer/AI lectures (search "computer history museum")
- Albert Hofmann's 1996 lecture on LSD (search "Hofmann LSD")
- Terence McKenna talks (CC-BY-NC by his estate — personal use OK)

**Your own collection:**
- Movies you own (DVDs/Blu-ray rips) for personal use is fair use in most jurisdictions
- Podcasts, YouTube clips with `yt-dlp` for personal use

## Converting clips

```bash
# Trim a section out of a longer file (start at 1:23, take 3 seconds)
ffmpeg -ss 00:01:23 -t 3 -i input.mp4 -ac 1 -ar 44100 -sample_fmt s16 voice_1.wav
```

Then `/beatpilot:music` (toggle off then on) to reload.
VOICEEOF

# ============ AMBIENT (percussion textures — metallic, resonant) ============
echo "  ambient..."
cp "$VD/perc/close/triangle/Triangle1_Hit_v1_rr1_Close.wav"          "$SAMPLES_DIR/ambient/triangle.wav"
cp "$VD/perc/close/belltree/BellTree_Stroke_rr1_Close.wav"           "$SAMPLES_DIR/ambient/belltree.wav"
cp "$VD/perc/close/sleighbells/Sleighbells_Hit_rr1_Close.wav"        "$SAMPLES_DIR/ambient/sleighbells.wav"
cp "$VD/perc/close/shaker/LShaker_Shake1D_rr1_Close.wav"             "$SAMPLES_DIR/ambient/shaker.wav"
cp "$VD/perc/close/cabasa/Cabasa1_Rub_v1_rr1_Close.wav"              "$SAMPLES_DIR/ambient/cabasa.wav"
convert "$VD/oh/crash/oh_crash_sizzle_vl1_rr1.flac"                  "$SAMPLES_DIR/ambient/sizzle.wav"
convert "$VD/oh/ride/oh_ride_ride_vl1_rr1.flac"                      "$SAMPLES_DIR/ambient/cymbal_wash.wav"

# ============ PIANO (Salamander Grand Piano V3 — CC0 by Alexander Holm) ============
echo "  piano (Salamander Grand Piano — ~74MB download)..."
mkdir -p "$SAMPLES_DIR/piano"
PIANO_TMP="/tmp/beatpilot-piano-$$"
mkdir -p "$PIANO_TMP"
PIANO_URL="https://archive.org/download/SalamanderGrandPianoV3/SalamanderGrandPianoV3_OggVorbis.tar.bz2"
if curl -fsSL "$PIANO_URL" -o "$PIANO_TMP/piano.tar.bz2"; then
    tar -xjf "$PIANO_TMP/piano.tar.bz2" -C "$PIANO_TMP" 2>/dev/null || true
    # Find the OggVorbis directory regardless of exact tarball layout
    SAL_DIR=$(find "$PIANO_TMP" -type d -name "OggVorbis" | head -1)
    if [ -z "$SAL_DIR" ]; then
        SAL_DIR=$(find "$PIANO_TMP" -type d -name "SalamanderGrandPianoV3*" | head -1)
    fi
    # 11 keyzones at v8 (medium-forte velocity) covering C2-C7 every 6 semitones
    # Salamander naming: A0v8.ogg ... C8v8.ogg (note name + octave + velocity)
    declare -a KEYS=("C2:36" "F#2:42" "C3:48" "F#3:54" "C4:60" "F#4:66" "C5:72" "F#5:78" "C6:84" "F#6:90" "C7:96")
    for entry in "${KEYS[@]}"; do
        name="${entry%:*}"
        midi="${entry#*:}"
        # Salamander uses 'b' for sharps in some sets; try both naming conventions
        src=$(find "$SAL_DIR" -type f \( -name "${name}v8.ogg" -o -name "${name//#/b}v8.ogg" \) | head -1)
        if [ -n "$src" ]; then
            ffmpeg -y -i "$src" -ac 1 -ar 44100 -sample_fmt s16 "$SAMPLES_DIR/piano/p${midi}.wav" -loglevel error
        else
            echo "    warning: could not find Salamander sample for ${name} (MIDI ${midi})"
        fi
    done
    rm -rf "$PIANO_TMP"
else
    echo "    skipped: could not download Salamander Grand Piano (piano genre will use FM synthesis)"
    rm -rf "$PIANO_TMP"
fi

# Clean up
echo "Cleaning up..."
rm -rf "$TMP_DIR"

# Write attribution
cat > "$SAMPLES_DIR/LICENSE.md" << 'LICEOF'
# Sample Attribution

## Drum samples (lofi, techno, dnb, dub, ambient, goa, reggae)

**Virtuosity Drums**
- Source: https://github.com/sfzinstruments/virtuosity_drums
- License: **CC0 1.0 Universal (Public Domain Dedication)**

## Piano samples (piano genre)

**Salamander Grand Piano V3** by Alexander Holm
- Source: https://archive.org/details/SalamanderGrandPianoV3
- License: **CC0 1.0 Universal (Public Domain Dedication)**
- Yamaha C5 grand recorded in stereo across 16 velocity layers; Beatpilot uses
  the v8 (medium-forte) layer at 11 keyzones every 6 semitones from C2-C7.

No attribution is legally required for either source, but we credit the creators
because it's the right thing to do.
LICEOF

# Count what we installed
total=$(find "$SAMPLES_DIR" -name "*.wav" | wc -l | tr -d ' ')
echo ""
echo "Installed $total samples across all genres."
echo "Samples directory: $SAMPLES_DIR"
echo ""
echo "Restart Beatpilot to use samples: /beatpilot:music (toggle off then on)"
