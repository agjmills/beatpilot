# beatpilot

A generative music soundtrack for your Claude Code sessions, powered by [ChucK](https://chuck.cs.princeton.edu/).

Music plays continuously while Claude works. The groove evolves in real-time — prompts, tool calls, agent spawns, and errors all shape what you hear. Each interaction produces a deterministic hash that influences the key, scale, and pattern, so the same prompt always produces the same musical fingerprint.

This entire project was vibecoded — built with Claude Code in a single session. It exists so you can vibe while you vibe.

## Genres

Switch genres with `/vibe <genre>` inside Claude, or `./vibe.sh <genre>` from the terminal.

| Genre | BPM | Vibe |
|-------|-----|------|
| **techno** | 128 | 4/4 kick, acid bass, minimal lead, drops and risers |
| **dnb** | 174 | Breakbeats, heavy sub bass, reese, atmospheric pads |
| **lofi** | 85 | Jazzy chords, brushy drums, vinyl crackle, mellow |
| **ambient** | 70 | No drums, slow drones, shimmering pads, pure texture |
| **dub** | 75 | One-drop drums, heavy sub bass, delay throws, skank guitar |

## How it works

```
Claude Code hooks  →  hook.sh  →  state file  →  genre engine (ChucK)
                                  /tmp/beatpilot-state
```

Each genre has its own ChucK engine in `genres/`. The engine runs a continuous sequencer that reads a state file once per bar. **hook.sh** is called by Claude Code on every prompt, tool call, and lifecycle event — it hashes the content, derives musical parameters, and writes them to the state file.

### Energy system

Events control an **energy** level (0–3) that determines which layers play:

| Energy | Triggered by | Techno | D&B | Lo-fi | Ambient |
|--------|-------------|--------|-----|-------|---------|
| 0 | Errors, inactivity | Silence | Silence | Silence | Silence |
| 1 | Stop, decay | Sparse kick | Kick + snare | Soft kick | Drone |
| 2 | Prompts, tools | Full groove + bass | + reese + pads | + keys + bass | + pads |
| 3 | Agents, Bash | + lead + drops | + busy breaks | (same as 2) | + shimmer |

Energy decays over time. If Claude goes idle, the groove strips back and eventually fades to silence.

### Content hashing

The text content of each event (prompt text, tool name, file paths, command strings) is hashed to produce:

- **Key** (0–11): root note of the groove
- **Scale** (0–3): varies per genre (pentatonic, minor, jazzy 7ths, etc.)
- **Seed** (0–255): selects pattern bank, offsets melody degrees

Same prompt = same musical fingerprint. Different prompts sound different.

### Transitions

Events can trigger musical transitions:

- **Riser + drop**: energy jumps up → kick drops out, noise sweeps up, hats fill, then everything slams back in with an impact hit
- **Breakdown**: energy drops → filters sweep down, layers strip away
- **Impact**: big low sine boom when the drop resolves

## Prerequisites

- **[ChucK](https://chuck.cs.princeton.edu/release/)** — the audio engine
  - macOS: `brew install chuck`
  - Linux: `sudo apt install chuck` or build from source
  - Windows: download from the ChucK website
- **jq** — for JSON parsing in hooks
  - macOS: `brew install jq`
  - Linux: `sudo apt install jq`

If you install the plugin without ChucK, you'll see a reminder message in Claude prompting you to install it.

## Installation

### Option A: Claude Code plugin (recommended)

```
/plugin marketplace add agjmills/beatpilot
/plugin install beatpilot@beatpilot
```

This registers the hooks automatically and gives you `/music` (toggle) and `/vibe` (switch genre) commands.

### Option B: Manual install

```bash
git clone https://github.com/agjmills/beatpilot.git
cd beatpilot
./install.sh
```

This adds hooks to your global `~/.claude/settings.json`. Restart Claude Code to activate.

### Option C: Global skills (for development)

If you want to develop beatpilot while using it in other projects, add it as an extra directory:

```bash
claude --add-dir /path/to/beatpilot
```

Or make it permanent with a shell alias:

```bash
# ~/.zshrc or ~/.bashrc
alias claude='claude --add-dir /path/to/beatpilot'
```

Alternatively, symlink the skills to your global Claude config:

```bash
ln -s /path/to/beatpilot/skills/bp:music ~/.claude/skills/bp:music
ln -s /path/to/beatpilot/skills/bp:vibe ~/.claude/skills/bp:vibe
ln -s /path/to/beatpilot/skills/bp:volume ~/.claude/skills/bp:volume
```

### Uninstall

```bash
# Manual install
./uninstall.sh

# Plugin install
/plugin uninstall beatpilot@beatpilot
```

## Usage

Once installed, music starts automatically when you begin a Claude session.

### Toggle on/off

```
/bp:music
```

Or from the terminal: `./toggle.sh`

### Switch genre

```
/bp:vibe dnb
/bp:vibe lofi
/bp:vibe ambient
/bp:vibe techno
/bp:vibe dub
```

Or from the terminal: `./vibe.sh dnb`

Run `/bp:vibe` or `./vibe.sh` with no argument to list available genres.

### Volume

```
/bp:volume 50
/bp:volume      # show current volume
```

Or from the terminal: `./volume.sh 50`

### Manual control

```bash
./start.sh    # Start the engine
./stop.sh     # Stop the engine
```

## File structure

```
beatpilot/
├── hook.sh                # Hook entry point — reads events, writes state
├── start.sh               # Start the ChucK engine
├── stop.sh                # Stop the engine
├── toggle.sh              # Toggle music on/off
├── vibe.sh                # Switch genre
├── install.sh             # Manual installer
├── uninstall.sh           # Manual uninstaller
├── volume.sh              # Set volume (0-100)
├── genres/
│   ├── techno.ck          # 128 BPM — kicks, acid bass, drops
│   ├── dnb.ck             # 174 BPM — breakbeats, reese, pads
│   ├── lofi.ck            # 85 BPM — jazzy chords, vinyl crackle
│   ├── ambient.ck         # 70 BPM — drones, shimmers, no drums
│   └── dub.ck             # 75 BPM — one-drop, delay throws, sub bass
├── .claude-plugin/
│   ├── plugin.json        # Plugin manifest
│   └── marketplace.json   # Marketplace definition
├── hooks/
│   └── hooks.json         # Hook config for plugin installs
└── skills/
    ├── bp:music/
    │   └── SKILL.md       # /bp:music — toggle on/off
    ├── bp:vibe/
    │   └── SKILL.md       # /bp:vibe — switch genre
    └── bp:volume/
        └── SKILL.md       # /bp:volume — set volume
```

## Customization

### Create your own genre

Copy an existing genre file and tweak it:

```bash
cp genres/techno.ck genres/mygenre.ck
# Edit BPM, patterns, synth parameters...
./vibe.sh mygenre
```

The engine structure is the same across genres — BPM, patterns, synth routing, and parameter values are what differ.

### Edit patterns

Patterns are 16-step arrays, one per energy level. Values are scale degrees (`0` = root, `1` = 2nd, etc.), `-1` = rest:

```chuck
// Bass pattern, energy 3: acid line with octave jumps
[ 0,-1, 5,-1, 0,-1,-1, 3, 0,-1,-1, 7, 0,-1, 5,-1]
```

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

## How the audio works

Everything is synthesized in real-time by ChucK. No samples or external dependencies.

- **Kick**: SinOsc with rapid pitch decay through LPF + noise click transient
- **Hats**: Noise through high-pass filters with short ADSR envelopes
- **Clap/Snare**: Noise through band-pass with shaped decay
- **Bass**: TriOsc through resonant LPF with per-note filter envelope
- **Lead**: TriOsc (probabilistic generation — random notes each bar, never repeats)
- **Pads/Keys**: Layered TriOsc/SinOsc with slow amplitude envelopes
- **Transitions**: Noise riser sweep + SinOsc impact boom

## License

MIT
