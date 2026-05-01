# Beatpilot — Sound Design Guidelines

## Core Principles

Every genre engine must feel like **music**, not a tech demo. These are the non-negotiable foundations learned from building the existing engines:

### 1. Never use bare oscillators
Raw SinOsc/TriOsc/SawOsc sound like test tones. Every melodic/harmonic voice needs:
- **Detuned pairs** (±0.2-0.3%) for width and warmth
- **Slow pitch drift LFO** on one of the pair (rate ~0.0001) so the sound lives and breathes
- **Filter with movement** — LFO or envelope, never static. Even a gentle sweep transforms a tone.

### 2. Everything needs space
Dry signals sound like a phone off the hook. Every engine must include:
- **Multi-tap delay reverb** (4 taps, prime-ratio delay times, cross-fed with feedback + LP darkening)
- Typical settings: feedback 0.3-0.45, LP cutoff 1500-3000Hz depending on genre brightness
- **Lead delay** — dotted-eighth or quarter-note feedback delay. Sparse melodies rely on delay to fill space.

### 3. Chord progressions, not random chords
Never `Math.random2()` for chord roots. Every engine needs:
- A `progs[][]` array of 4-chord progressions (at least 4 progressions, mix of warm and dark)
- Seed selects which progression — same seed = same harmony
- 16-bar phrase: each chord lasts 4 bars
- **All harmonic elements follow the progression**: bass, pad, lead, stab — all offset by `chordRoot`

### 4. Lead motif, not random notes
The lead must play a **repeating phrase**, not dice-roll notes each step:
- 4-bar (64-step) phrase generated deterministically from seed
- Structure: call → response → development → resolution
- Sparse — leave space for delay echoes
- Phrase is transposed by `chordRoot` each chord change, so it moves with the harmony
- Same seed = same melody every time

**Critical: cell-based composition, not scale walking.** Walking up and down a scale sounds like a finger exercise. Real melodies use a short **cell** (2-3 note figure) that gets repeated with variation:
- Generate a **cell** from seed: 3 notes with specific intervals + a rhythm template (step positions)
- The cell's first interval (`leap1`) comes from a pool like `[1, 2, -1, 2, 1, -2]` — this gives the melody its character
- The third note resolves: `cellDeg[1] + resolve` where resolve comes from `[-1, 0, 1, -1, 0]`
- **Bar 1**: play the cell (establish the idea)
- **Bar 2**: play the cell **varied** — seed picks: transpose up a 3rd, invert (flip intervals), or retrograde (backwards)
- **Bar 3**: play the cell **twice** — first transposed higher, then original with an approach note (step below) leading in
- **Bar 4**: half the cell + resolve to root (degree 0) — **always**
- The approach note in bar 3 (`cellDeg[0] - 1`) gives it a "someone who knows what they're doing" feel
- Repetition is what makes it sound composed. The listener hears the cell, recognizes it varied, and that's musicality.
- Different genres use different **cell rhythm spacing**: lofi = wide (0,4,6 or 0,6,8), techno = tight (0,2,4), DnB = spacious (0,6,12)

### 5. Swing
Straight 16ths sound robotic. Every engine needs swing:
- Implemented by varying step duration: even steps get `stepDur * 2 * swingAmt`, odd steps get the remainder
- `0.5` = straight, `0.58` = subtle (DnB), `0.62` = groovy (techno), `0.63` = heavy (lofi)
- Genre-appropriate — lofi is heavier than techno

### 6. Velocity and dynamics
Every hit at the same volume = lifeless. Add:
- **Velocity arrays** per instrument (0.0-1.0 per step)
- Ghost notes on hats/snares at 25-35% volume
- Kick accents on beat 1, softer on off-beats
- Lead phrase contour: bar 3 peaks, bar 4 pulls back
- Hat fills should crescendo

### 7. Idle behavior — graceful fadeout and dramatic intros
When Claude is idle for a long time (10+ bars with no events):
- Energy decays naturally through the existing decay mechanism
- Once energy reaches 0, `masterTarget` fades to 0.0 — the music fades out gracefully
- No auto-evolution cycles — silence is preferable to aimless noodling

**"Call to the dancefloor" intro** — when music returns from silence (~50% chance, only at energy >= 2):
- HPF starts high (genre-specific: lofi 800Hz, techno 2500Hz, DnB 2000Hz, dub 1000Hz, ambient 400Hz)
- Sweeps down over 2 or 4 bars using quadratic curve: `startFreq * (1-p)² + 20`
- Reverb/delay gets boosted during the sweep (washy, anticipatory)
- On the final bar: HPF snaps to 20Hz, reverb/delay snaps to base values — the "drop"
- The effect: thin, filtered, spacious → builds → FULL GROOVE LANDS
- Triggered in `readState()` when `masterTarget < 0.01` (was silent) and `newEnergy >= 2`
- Progression runs in bar boundary; FX trigger and FX release are gated on `!introActive`
- Substep HPF smoothing is also gated on `!introActive` so the bar-by-bar sweep isn't fought

### 7b. Drum fills at phrase boundaries
Fills give the track rhythmic punctuation and make it feel composed, not looped:
- **Small fill** every 4 bars (`phraseBar % 4 == 3`): subtle — a few extra ghost hits in the last quarter of the bar
- **Big fill** every 16 bars (`phraseBar == 15`): builds through the bar — snare/hat rolls with crescendo velocity
- Only play fills when `energy >= 1` and motif is generated
- Fill hits should only fire where normal patterns are silent (don't double-trigger)
- Genre character: lofi = brush flurries, techno = hat+clap rolls, DnB = breakbeat snare rolls, dub = rimshot into delay

### 8. Bass derived from the cell, not fixed patterns
The bass line must share DNA with the lead — both come from the same cell. Fixed pattern arrays (`bPatA[][]`) sound disconnected, like a preset backing track under a solo.
- Generate a `bassLine[64]` array in `generateMotif()` using the same `cellDeg` and `leap1` variables
- Bass plays **root on strong beats**, cell interval as **passing tone** on off-beats
- Bar 2 bass follows the same variation type as the lead (transpose/invert/retrograde)
- Bar 3 bass gets busier (mirrors lead development)
- Bar 4 bass simplifies — just roots, resolving
- The listener hears bass and lead as parts of the same piece because they share the same intervals

### 9. Arrangement mask — not everything plays all the time
A track where every layer loops from bar 1 sounds like a tech demo. Real music has **structure** — layers enter, exit, and interact across the phrase.
- Generate an `arrangement[16]` array in `generateMotif()` — one entry per bar of the 16-bar phrase
- Levels: `0` = minimal, `1` = bass, `2` = bass + pad/keys, `3` = bass + pad + lead
- Seed selects from arrangement templates:
  - **Build**: bass only → +pad → +lead → strip back (1,1,1,1, 2,2,2,2, 3,3,3,3, 2,2,1,1)
  - **Call-response**: lead bars alternate with bass-only (1,1,3,3, 1,1,3,3, 2,2,3,3, 3,3,2,1)
  - **Full-then-strip**: everything up front, then layers drop (2,2,3,3, 3,3,3,3, 2,2,2,2, 1,1,2,2)
- In the sequencer, read `arrangement[phraseBar]` and only trigger layers at or above the current level
- When a layer is gated off, fade its target to 0 — don't hard-cut

### 10. Pad/keys dynamics follow the phrase
Static pad = lifeless drone. The pad should breathe with the harmonic rhythm:
- Bars 1-2 of each chord: gentle (0.03-0.04 gain target)
- Bar 3: peak (0.07-0.08) — this is where the phrase builds
- Bar 4: pull back (0.02-0.03) — creates space before the next chord
- Filter should open progressively through the 4-bar chord cycle
- At energy 3, multiply gain targets by ~1.3 for more presence

### 11. Instrument choices by genre feel

| Element | Warm/Mellow | Atmospheric | Aggressive | Dark/Tense |
|---------|------------|-------------|------------|------------|
| Lead | FM (2:1 ratio, low mod depth 30-40) | FM (3:2, mod depth 60-80) | Saw + steep LPF | FM (high mod depth 80+) |
| Pad | Detuned TriOsc pairs | Detuned TriOsc + SinOsc | SawOsc pairs | TriOsc pairs, darker filter |
| Bass | SinOsc (pure sub) | SinOsc + TriOsc layer | SawOsc detuned (reese) | TriOsc through low LPF |
| Keys | Detuned TriOsc + 7th voice | - | SawOsc stabs | - |

FM mod ratios: 2:1 = warm/Rhodes, 3:2 = glassy/bell, 5:3 = metallic, 1:1 = bright

### 12. Scale selection
Don't limit to just pentatonics. Include:
- **Warm**: pentatonic major, pentatonic minor, major 7, lydian
- **Dark**: harmonic minor (raised 7th = cinematic), phrygian (flat 2 = dread), natural minor
- **Tension**: whole-half diminished, chromatic clusters
- Let seed/mood determine which pool to draw from

### 14. Occasional FX for tension and release
A track that never changes its effects sounds static. Occasional FX moments give it the dynamics of a DJ turning knobs:
- **When**: ~40% chance at bar 12 of each 16-bar phrase (gives 4 bars of buildup before phrase reset). Only triggers at energy >= 2 and not during transitions.
- **Seed-deterministic**: `(seed * 7 + stepCount / 320) % 5` — same seed gets same FX pattern but varies over time.
- **Three FX types** (seed selects which):
  1. **HPF sweep**: Master bus high-pass filter sweeps up, thinning the mix. Genre ranges: lofi 800Hz, techno 2000Hz, DnB 1500Hz, dub 600Hz, ambient 400Hz. Uses quadratic curve (`p * p`) for natural acceleration.
  2. **Reverb wash**: Boosts reverb mix gain and feedback. Everything gets spacious and washy. Reverb returns to base values via smooth decay when FX ends.
  3. **Third FX** (genre-specific): Delay feedback swell (lofi/DnB/techno), dub delay throw swell (dub), or shimmer boost (ambient).
- **Release**: When the FX ends, parameters don't snap back — they smooth-decay toward base values (0.95 * current + 0.05 * base per bar for reverb/delay, substep smoothing for HPF).
- **Signal chain**: All engines route through `Gain masterOut => HPF fxHPF => dac` with the HPF normally at 20Hz (transparent). Both dry and reverb outputs feed `masterOut`.

### 15. Motif variation across repetitions
The same 4-bar motif repeating identically sounds like a loop, not a performance. Each repetition within the 16-bar phrase gets subtle changes:
- **Rep 0** (bars 0-3): Play motif as written — establish the idea
- **Rep 1** (bars 4-7): Drop one note (`(seed + phraseStep) % 5 == 0` → set deg to -1) — creates a "question" feel
- **Rep 2** (bars 8-11): Octave jump on bar 3 peak notes — intensification
- **Rep 3** (bars 12-15): Approach note from below on selected steps (`deg - 1`) — resolution with ornamentation
- Applied in the lead playback section, not in `generateMotif()` — the motif array stays clean, variations are applied on read

### 16. Chord substitutions
Repeating the same 4 chords forever becomes wallpaper. Every 3rd cycle of the 16-bar phrase (`phraseRepeat % 3 == 2`), substitute one chord:
- `(seed * 13 + phraseRepeat) % 4` picks which chord to replace
- Genre-specific substitution flavor: lofi = up a 3rd (jazz tritone-ish), techno = up 2 degrees (modal interchange), DnB = up 1 degree (chromatic approach), dub = up 3 degrees (up a 4th), ambient = up 5 degrees (deceptive resolution)
- Applied via `chordSub[4]` array (-1 = no sub) checked after reading `progs[progIdx][chordIdx]`
- Reset on new state events and at each phrase boundary

### 17. Drum micro-variation
Static drum patterns are the #1 giveaway of machine-generated music. Add seed-deterministic per-bar mutations:
- `(seed + phraseBar * 7) % 8` gives a variation value per bar
- Low values: add a ghost hat on an empty step; high values: add a ghost snare
- Only at energy >= 2 (don't vary minimal patterns)
- Genre-specific step positions: lofi = steps 5/11, techno = steps 3/7, DnB = steps 7/9, dub = steps 5/9
- Ambient has no drums, so no variation needed

### 18. Per-note velocity humanization
Even ±5% variation per hit makes the difference between "sequenced" and "played":
- `((seed * 17 + stepCount) % 100 - 50) / 1000.0` gives -0.05 to +0.05 jitter
- Applied to kick and hat velocity calculations in all engines
- Fully deterministic — same seed + same step = same jitter

### 19. Dynamic filter LFO rate
A fixed LFO rate makes pads sound like static drones. Tie the rate to arrangement and phrase position:
- Base rate: genre-specific (lofi 0.0008, techno 0.002, DnB 0.001, dub 0.0015, ambient 0.0012)
- × 1.4-1.5 when `arrLevel >= 3` (full arrangement = faster modulation)
- × 1.3 at bar 3 of each chord (`phraseBar % 4 == 2` = peak moment)
- × 0.7 at bars 12-15 (`phraseBar >= 12` = phrase end, calmer)

### 13. State file interface
All engines read `/tmp/beatpilot-state` with the same format:
```
energy (0-3)
key (0-11)
scale (index)
seed (0-255)
timestamp
```
Read once per bar (step 0). Only act on new timestamps.

## Adding a New Genre

1. Copy the closest existing engine as a starting point
2. Set BPM and swing amount appropriate to genre
3. Define drum patterns (4 energy levels × 16 steps) + ghost patterns
4. Define chord progressions (at least 4, mix of moods)
5. Define scales appropriate to genre
6. Build cell-based motif generator (4-bar lead phrase, seed-deterministic)
7. Build bass line in the same generator, derived from the cell intervals
8. Build arrangement mask (16 bars, 3 templates based on seed)
9. Wire everything through `masterOut => HPF fxHPF => dac` (dry + reverb both feed `masterOut`)
10. Add drum fill logic (small fill every 4 bars, big fill every 16 bars)
11. Add idle fadeout (`masterTarget` → 0.0 when energy == 0 and idle > threshold) + intro system
12. Add velocity maps for all drums
13. Ensure pad/keys dynamics follow the 4-bar phrase arc (swell → peak → pull back)
14. Add occasional FX system (HPF sweep, reverb wash, genre-specific third FX)
15. Add motif variation (rep 0: as-is, rep 1: drop note, rep 2: octave jump, rep 3: approach notes)
16. Add chord substitution system (`phraseRepeat`, `chordSub[4]`)
17. Add drum micro-variation (seed-deterministic ghost note mutations per bar)
18. Add per-note velocity humanization (±5% jitter on kicks and hats)
19. Add dynamic filter LFO rate (faster during builds, slower at phrase end)
20. Test: does it sound like a composed piece or a tech demo? Check:
    - Do bass and lead share the same intervals? (principle 8)
    - Do layers come and go, or is everything on from bar 1? (principle 9)
    - Does the pad breathe, or is it a static drone? (principle 10)
    - Can you hear the cell repeat and vary, or does it sound random? (principle 4)
    - Do you hear occasional FX moments (filter sweeps, reverb washes), or is it static? (principle 14)
    - Does the melody vary each time through, or repeat identically? (principle 15)
    - Does the harmony ever surprise you, or is it completely predictable? (principle 16)
    - Do the drums feel alive with micro-variations, or perfectly machine-quantized? (principle 17)

## Making Skills Available Globally

The `/music` and `/vibe` skills live in this repo's `skills/` directory. To make them available in all Claude Code sessions (not just when working in this repo):

### Option A: `--add-dir` flag (recommended for development)

```bash
claude --add-dir /path/to/beatpilot
```

This loads skills from this repo into any session. Add an alias to your shell config to make it permanent:

```bash
# ~/.zshrc or ~/.bashrc
alias claude='claude --add-dir /path/to/beatpilot'
```

### Option B: Symlink to global skills directory

```bash
ln -s /path/to/beatpilot/skills/music ~/.claude/skills/music
ln -s /path/to/beatpilot/skills/vibe ~/.claude/skills/vibe
```

Skills in `~/.claude/skills/` are available in all sessions automatically.

### Option C: Plugin install

```
/plugin marketplace add agjmills/beatpilot
/plugin install beatpilot@agjmills
```

This registers the hooks and skills automatically.

## Using with Other AI Tools (Copilot, Cursor, Codex, Aider, etc.)

Beatpilot works with **any** coding tool. The genre engines just read a state file — they don't care what writes it. Tools with hook systems (Copilot CLI) get first-class adapters; everything else uses the file watcher.

### GitHub Copilot CLI (first-class — hooks)

Add to `~/.copilot/config.json`:

```json
{
  "hooks": {
    "userPromptSubmitted": [{ "type": "command", "bash": "/path/to/beatpilot/adapters/copilot-cli.sh" }],
    "preToolUse":          [{ "type": "command", "bash": "/path/to/beatpilot/adapters/copilot-cli.sh" }],
    "postToolUse":         [{ "type": "command", "bash": "/path/to/beatpilot/adapters/copilot-cli.sh" }],
    "errorOccurred":       [{ "type": "command", "bash": "/path/to/beatpilot/adapters/copilot-cli.sh" }],
    "sessionStart":        [{ "type": "command", "bash": "/path/to/beatpilot/adapters/copilot-cli.sh" }],
    "sessionEnd":          [{ "type": "command", "bash": "/path/to/beatpilot/adapters/copilot-cli.sh" }]
  }
}
```

Or place in `.github/hooks/` in your repo for project-level hooks.

### File watcher (universal — Cursor, Codex, Aider, anything else)

```bash
# Start watching your project directory
/path/to/beatpilot/adapters/filewatcher.sh /path/to/your/project

# Stop watching
/path/to/beatpilot/adapters/filewatcher.sh --stop
```

The watcher monitors file changes and maps activity frequency to energy levels. Uses `fswatch` if installed (event-driven, efficient), otherwise polls with `find` every 3 seconds.

Add to your shell profile to auto-start with any project:
```bash
# ~/.zshrc or ~/.bashrc
beatpilot-watch() { /path/to/beatpilot/adapters/filewatcher.sh "${1:-.}"; }
```

### Direct state control (for custom integrations)

```bash
# Write state directly: write-state.sh <energy 0-3> [content for variation]
/path/to/beatpilot/adapters/write-state.sh 2 "editing main.py"
/path/to/beatpilot/adapters/write-state.sh 3 "running tests"
/path/to/beatpilot/adapters/write-state.sh 0 "build failed"
```

This is the building block for writing your own adapter for any tool.

## Adapter Architecture

```
adapters/
  write-state.sh    — shared core: hashes content → key/scale/seed, writes state
  claude-code.sh    — Claude Code adapter (receives hook JSON on stdin)
  copilot-cli.sh    — GitHub Copilot CLI adapter (receives hook JSON on stdin)
  filewatcher.sh    — universal adapter (watches filesystem for changes)
hook.sh             — thin wrapper → adapters/claude-code.sh (backwards compat)
```

All adapters call `write-state.sh`, which handles:
- MD5 hashing of content into musical parameters (key, scale, seed)
- Atomic state file writes to `/tmp/beatpilot-state`
- Auto-starting the ChucK engine if not running

## File Structure
- `genres/*.ck` — genre engines (one per genre)
- `adapters/` — client adapters (Claude Code, file watcher, write-state core)
- `hook.sh` — Claude Code hook entry point (forwards to adapter)
- `start.sh` / `stop.sh` / `toggle.sh` — engine lifecycle
- `vibe.sh` — genre switcher
- `volume.sh` — volume control (0-100)
- `skills/` — Claude Code slash commands (`/beatpilot:music`, `/beatpilot:vibe`, `/beatpilot:volume`)
