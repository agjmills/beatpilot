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

### 7. Idle behavior — graceful fadeout
When Claude is idle for a long time (10+ bars with no events):
- Energy decays naturally through the existing decay mechanism
- Once energy reaches 0, `masterTarget` fades to 0.0 — the music fades out gracefully
- A new event from Claude immediately sets `masterTarget` back to 1.0 and resets energy
- No auto-evolution cycles — silence is preferable to aimless noodling

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
9. Wire everything through the reverb bus
10. Add drum fill logic (small fill every 4 bars, big fill every 16 bars)
11. Add idle fadeout (`masterTarget` → 0.0 when energy == 0 and idle > threshold)
12. Add velocity maps for all drums
13. Ensure pad/keys dynamics follow the 4-bar phrase arc (swell → peak → pull back)
14. Test: does it sound like a composed piece or a tech demo? Check:
    - Do bass and lead share the same intervals? (principle 8)
    - Do layers come and go, or is everything on from bar 1? (principle 9)
    - Does the pad breathe, or is it a static drone? (principle 10)
    - Can you hear the cell repeat and vary, or does it sound random? (principle 4)

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
/plugin install beatpilot@beatpilot
```

This registers the hooks and skills automatically.

## File Structure
- `genres/*.ck` — genre engines (one per genre)
- `hook.sh` — event handler, writes state file
- `start.sh` / `stop.sh` / `toggle.sh` — engine lifecycle
- `vibe.sh` — genre switcher
- `volume.sh` — volume control (0-100)
- `skills/` — Claude Code slash commands (`/bp:music`, `/bp:vibe`, `/bp:volume`)
