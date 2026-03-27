# beatpilot

A generative techno soundtrack for your Claude Code sessions, powered by [ChucK](https://chuck.cs.princeton.edu/).

Music plays continuously while Claude works. The groove evolves in real-time — prompts, tool calls, agent spawns, and errors all shape what you hear. Each interaction produces a deterministic hash that influences the key, scale, and pattern, so the same prompt always produces the same musical fingerprint.

This entire project was vibecoded — built with Claude Code in a single session. It exists so you can vibe while you vibe.

## How it works

```
Claude Code hooks  →  hook.sh  →  state file  →  engine.ck (ChucK)
                                  /tmp/beatpilot-state
```

**engine.ck** is a 128 BPM techno sequencer with layered instruments (kick, hats, clap, acid bass, lead synth). It reads a state file once per bar to check for updates.

**hook.sh** is called by Claude Code hooks on every prompt, tool call, and lifecycle event. It hashes the content, derives musical parameters (key, scale, seed), and writes them to the state file.

### Energy system

Events control an **energy** level (0–3) that determines which layers play:

| Energy | Layers | Triggered by |
|--------|--------|-------------|
| 0 | Silence (fading out) | Errors, prolonged inactivity |
| 1 | Sparse kick | Stop events, energy decay |
| 2 | Full groove: kick + hats + bass + clap | Prompts, tool calls |
| 3 | Intense: driving kicks, busy hats, lead synth | Agent spawns, Bash commands |

Energy decays over time. If Claude goes idle, the groove strips back and eventually fades to silence.

### Content hashing

The text content of each event (prompt text, tool name, file paths, command strings) is hashed to produce:

- **Key** (0–11): root note of the groove
- **Scale** (0–3): major pentatonic, minor pentatonic, major, or minor
- **Seed** (0–255): selects pattern bank (A/B), rotates percussion, offsets melody degrees

This means the same prompt always triggers the same musical response, but different prompts sound different.

## Prerequisites

- **[ChucK](https://chuck.cs.princeton.edu/release/)** — the audio engine
  - macOS: `brew install chuck`
  - Linux: `sudo apt install chuck` or build from source
  - Windows: download from the ChucK website
- **jq** — for JSON parsing in hooks
  - macOS: `brew install jq`
  - Linux: `sudo apt install jq`

## Installation

### Option A: Claude Code plugin (recommended)

```bash
# Add the marketplace and install
/plugin marketplace add your-username/beatpilot
/plugin install beatpilot
```

This registers the hooks automatically and gives you the `/music` slash command to toggle on/off.

### Option B: Manual install

```bash
git clone https://github.com/your-username/beatpilot.git
cd beatpilot
./install.sh
```

This adds hooks to your global `~/.claude/settings.json`. Restart Claude Code to activate.

### Uninstall

```bash
# Manual install
./uninstall.sh

# Plugin install
/plugin uninstall beatpilot
```

## Usage

Once installed, music starts automatically when you begin a Claude session. No action needed.

### Toggle on/off

From within Claude:
```
/music
```

From the terminal:
```bash
./toggle.sh
```

### Manual control

```bash
./start.sh    # Start the ChucK engine
./stop.sh     # Stop the engine
```

## File structure

```
beatpilot/
├── engine.ck              # Main sequencer — the brain
├── hook.sh                # Hook entry point — reads events, writes state
├── start.sh               # Start the ChucK engine
├── stop.sh                # Stop the ChucK engine
├── toggle.sh              # Toggle music on/off
├── install.sh             # Manual installer
├── uninstall.sh           # Manual uninstaller
├── .claude-plugin/
│   ├── plugin.json        # Plugin manifest
│   └── marketplace.json   # Marketplace definition
├── hooks/
│   └── hooks.json         # Hook config for plugin installs
└── skills/
    └── music/
        └── SKILL.md       # /music slash command
```

## Customization

### Change the tempo

Edit `engine.ck`, line 7:
```chuck
128.0 => float BPM;  // change this
```

### Edit patterns

Patterns are 16-step arrays in `engine.ck`. Each instrument has patterns per energy level (0–3), with two banks (A/B) for bass and lead:

```chuck
// Bass bank A, energy 3: acid line with octave jumps
[ 0,-1, 5,-1, 0,-1,-1, 3, 0,-1,-1, 7, 0,-1, 5,-1]
```

Values are scale degrees (`0` = root, `1` = 2nd, etc.), `-1` = rest.

### Change the energy mapping

Edit `hook.sh` to change which events set which energy levels:

```bash
case "$event" in
    UserPromptSubmit)  energy=2 ;;
    SubagentStart)     energy=3 ;;
    Stop)              energy=1 ;;
    # ...
esac
```

### Add new instruments

Add oscillators and pattern arrays in `engine.ck` following the existing pattern. Route through `master` for volume control:

```chuck
SinOsc myOsc => Gain myG => master;
```

## How the audio works

The engine uses ChucK's real-time audio synthesis:

- **Kick**: SinOsc with rapid pitch decay (180Hz → 42Hz) — classic 808 technique
- **Hats**: Noise through high-pass and band-pass filters with short ADSR envelopes
- **Clap**: Noise through a band-pass with medium decay
- **Bass**: SawOsc through resonant LPF (Q=9) with per-note filter envelope — acid squelch
- **Lead**: TriOsc (warm) through LPF (Q=3), sparse wide intervals to avoid siren effect

All sounds are synthesized in real-time. No samples or external dependencies beyond ChucK itself.

## License

MIT
