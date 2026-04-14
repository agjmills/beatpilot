# Beatpilot

**Generative music that plays while you code.** Five genres, real-time synthesis, zero samples. Your coding activity shapes what you hear — prompts, tool calls, file edits, and errors all influence the key, scale, energy, and melody.

Works with **Claude Code**, **GitHub Copilot CLI**, **Cursor**, **Codex**, **Aider**, and anything else that edits files.

Built entirely with Claude Code. It exists so you can vibe while you vibe.

https://github.com/user-attachments/assets/placeholder

## Quick start

### 1. Install ChucK (the audio engine)

```bash
# macOS
brew install chuck

# Linux
sudo apt install chuck

# Windows — download from https://chuck.cs.princeton.edu/release/
```

### 2. Install Beatpilot

**Claude Code plugin (recommended):**
```
/plugin marketplace add agjmills/beatpilot
/plugin install beatpilot@beatpilot
```

**Manual:**
```bash
git clone https://github.com/agjmills/beatpilot.git
cd beatpilot
./install.sh
```

### 3. Code. Music plays.

That's it. Music starts when you start coding and fades out when you stop.

## Genres

Switch with `/vibe <genre>` in Claude Code, or `./vibe.sh <genre>` from the terminal.

| Genre | BPM | Character |
|-------|-----|-----------|
| **techno** | 128 | Four-on-the-floor kick, acid bass, minimal lead, drops and risers |
| **dnb** | 174 | Breakbeats, heavy sub bass, reese, atmospheric pads, snare rolls |
| **lofi** | 85 | Jazzy vibraphone chords, brushy drums, vinyl crackle, Rhodey lead |
| **dub** | 75 | One-drop rhythm, massive delay throws, melodica lead, skank guitar |
| **ambient** | 70 | No drums. Evolving drones, shimmering pads, slow arpeggios, pure texture |

## Works with any AI coding tool

Beatpilot doesn't care what writes the code — it just needs to know something is happening. There are three ways to connect it:

### Claude Code (hooks — built in)

The plugin install wires this up automatically. Hooks fire on every prompt, tool call, agent spawn, and error.

### GitHub Copilot CLI (hooks)

Add to `~/.copilot/config.json`:

```json
{
  "hooks": {
    "userPromptSubmitted": [{ "type": "command", "bash": "/path/to/beatpilot/adapters/copilot-cli.sh" }],
    "preToolUse":          [{ "type": "command", "bash": "/path/to/beatpilot/adapters/copilot-cli.sh" }],
    "postToolUse":         [{ "type": "command", "bash": "/path/to/beatpilot/adapters/copilot-cli.sh" }],
    "errorOccurred":       [{ "type": "command", "bash": "/path/to/beatpilot/adapters/copilot-cli.sh" }]
  }
}
```

### Cursor, Codex, Aider, or anything else (file watcher)

```bash
# Start watching your project directory
./adapters/filewatcher.sh /path/to/your/project

# Stop watching
./adapters/filewatcher.sh --stop
```

The watcher monitors file changes and maps activity frequency to energy levels. Uses `fswatch` if available (event-driven), otherwise polls with `find`.

Add to your shell profile to auto-start:
```bash
# ~/.zshrc or ~/.bashrc
beatpilot-watch() { /path/to/beatpilot/adapters/filewatcher.sh "${1:-.}"; }
```

### Direct state control (for custom integrations)

```bash
# write-state.sh <energy 0-3> [content for musical variation]
./adapters/write-state.sh 2 "editing main.py"
./adapters/write-state.sh 3 "running tests"
./adapters/write-state.sh 0 "build failed"
```

## How it sounds

This isn't random notes over a drum loop. Every engine uses techniques from real composition:

- **Cell-based melodies** — a short 2-3 note figure gets repeated, transposed, inverted, and developed across a 4-bar phrase. Like a real composer working with a motif.
- **Bass derived from the lead** — both instruments share the same melodic DNA, so they sound like parts of the same piece.
- **Arrangement masks** — layers enter and exit across 16-bar phrases. Not everything plays all the time.
- **Chord progressions** — 4-chord sequences with occasional substitutions for harmonic surprise (jazz tritone subs in lofi, modal interchange in techno, etc.)
- **Motif variation** — the melody changes subtly each time it repeats: dropped notes, octave jumps, approach notes. Your ear never gets bored.
- **Drum micro-variation** — ghost notes shift bar to bar. No two bars are perfectly identical.
- **Velocity humanization** — every hit has ±5% jitter. Subtle, but the difference between "music" and "MIDI playback."
- **Occasional FX** — filter sweeps, reverb washes, delay swells. ~40% chance at phrase boundaries, like a DJ turning knobs.
- **Dramatic intros** — when music returns from silence, ~50% chance of a filtered buildup that sweeps open and drops into the full groove.
- **Swing** — every genre has genre-appropriate shuffle. Lofi is heavy, DnB is subtle, techno sits in between.

All of this is **seed-deterministic** — the same coding activity produces the same musical result every time.

## Energy system

Your activity controls an **energy** level (0–3) that determines how many layers play:

| Energy | What plays | Triggered by |
|--------|-----------|-------------|
| **0** | Silence (fadeout) | Inactivity, errors |
| **1** | Kick + basic rhythm | Decay from higher levels |
| **2** | + bass, pads/keys, full groove | Prompts, file edits, tool calls |
| **3** | + lead melody, full arrangement | Agent spawns, complex operations |

Energy decays naturally over time. If your AI tool goes idle, the music strips back layer by layer and eventually fades to silence. When activity resumes, it builds back up — sometimes with a dramatic filtered intro.

## Content hashing

The text content of each event is MD5-hashed to produce musical parameters:

- **Key** (0–11) — root note
- **Scale** (index) — genre-specific (pentatonic, minor, jazzy 7ths, harmonic minor, etc.)
- **Seed** (0–255) — selects chord progression, motif shape, arrangement template

Same prompt = same musical fingerprint. Different prompts sound different. Your codebase has a soundtrack.

## Controls

### In Claude Code

```
/music          Toggle on/off
/vibe dnb       Switch genre
/volume 50      Set volume (0-100)
```

### From the terminal

```bash
./toggle.sh          # Toggle on/off
./vibe.sh dnb        # Switch genre
./volume.sh 50       # Set volume
./start.sh           # Start engine
./stop.sh            # Stop engine
```

## File structure

```
beatpilot/
├── adapters/
│   ├── write-state.sh      # Core: hashes content → musical params → state file
│   ├── claude-code.sh      # Claude Code adapter (hook JSON on stdin)
│   ├── copilot-cli.sh      # GitHub Copilot CLI adapter
│   └── filewatcher.sh      # Universal adapter (watches filesystem)
├── genres/
│   ├── techno.ck            # 128 BPM — kicks, acid, drops
│   ├── dnb.ck               # 174 BPM — breakbeats, reese, atmosphere
│   ├── lofi.ck              # 85 BPM — jazz chords, vinyl, Rhodey
│   ├── dub.ck               # 75 BPM — one-drop, delay throws, sub
│   └── ambient.ck           # 70 BPM — drones, shimmer, no drums
├── skills/                  # Claude Code slash commands
├── hook.sh                  # Claude Code hook entry point
├── start.sh / stop.sh / toggle.sh / vibe.sh / volume.sh
└── install.sh / uninstall.sh
```

## Create your own genre

```bash
cp genres/techno.ck genres/house.ck
# Edit BPM, drum patterns, synth params, chord progressions...
./vibe.sh house
```

See `CLAUDE.md` for the full sound design guidelines — 19 principles covering everything from cell-based composition to reverb tuning. It's a complete handbook for building a genre engine that sounds like music, not a tech demo.

## How the audio works

Everything is synthesized in real-time by [ChucK](https://chuck.cs.princeton.edu/). No samples, no external dependencies, no DAW. Just math and oscillators.

- **Drums**: SinOsc pitch sweeps (kick), filtered noise with ADSR (hats/snare/clap)
- **Bass**: SinOsc/TriOsc through resonant LPF with per-note filter envelopes
- **Lead**: FM synthesis (DnB), Rhodey model (lofi), detuned oscillator pairs (techno/dub)
- **Pads**: Detuned TriOsc pairs with slow filter LFO, breathing dynamics
- **Effects**: 4-tap cross-fed delay reverb, lead delay with feedback, master HPF for sweeps
- **Dub special**: Dedicated delay throw bus — select notes get "thrown" into a high-feedback delay

## Prerequisites

- **[ChucK](https://chuck.cs.princeton.edu/release/)** — `brew install chuck` / `apt install chuck`
- **jq** — `brew install jq` / `apt install jq` (for JSON parsing in hooks)
- **md5sum** or **md5** (included on macOS/Linux)
- Optional: **fswatch** for efficient file watching (`brew install fswatch`)

## Uninstall

```bash
# Plugin
/plugin uninstall beatpilot@beatpilot

# Manual
./uninstall.sh
```

## License

MIT
