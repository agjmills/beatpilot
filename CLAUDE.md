# Beatpilot — Sound Design Guidelines

## Core Principles

Every genre engine must feel like **music**, not a tech demo. These are the non-negotiable foundations learned from building the existing engines:

### 1. Never use bare oscillators
Raw SinOsc/TriOsc/SawOsc sound like test tones. Every melodic/harmonic voice needs:
- **Detuned pairs** (±0.2-0.3%) for width and warmth
- **Slow pitch drift LFO** on one of the pair (rate ~0.0001) so the sound lives and breathes
- **Filter with movement** — LFO or envelope, never static. Even a gentle sweep transforms a tone.
- **An amplitude envelope on every note** (ADSR/Envelope with a real attack and release). Smoothing a gain target toward a level is not an envelope: it turns a melody into one sustained tone sliding between pitches.

### 2. Everything needs space
Dry signals sound like a phone off the hook. Every engine must include:
- **Multi-tap delay reverb** (4 taps, prime-ratio delay times, cross-fed with feedback + LP darkening)
- Typical settings: feedback 0.3-0.45, LP cutoff 1500-3000Hz depending on genre brightness
- **Lead delay** — dotted-eighth or quarter-note feedback delay. Sparse melodies rely on delay to fill space.
- **Tap the wet signal outside the feedback loop.** `in => DelayL d => Gain fb => d` with the output taken from `d`, and a separate wet gain into the mix. Putting a small wet gain inside the loop multiplies it into every echo: several engines had echoes 30-70 dB down, which is the same as no delay. Aim for the first echo within ~6-10 dB of the dry note.
- **High-pass the reverb send (~200-250 Hz).** Kick and sub in the reverb is mud.

### 3. Chord progressions, not random chords
Never `Math.random2()` for chord roots. Every engine needs:
- A `progs[][]` array of 4-chord progressions (at least 4 progressions, mix of warm and dark)
- Seed selects which progression — same seed = same harmony
- 16-bar phrase: each chord lasts 4 bars (at slow tempos that is too static; piano changes chord every bar)
- **All harmonic elements follow the progression**: bass, pad, lead, stab — all offset by `chordRoot`

### 3b. Degrees, chords and rests: the bugs every engine had
Most engines produced wrong notes for the same few reasons. These rules are not optional:
- **Chords come from a 7-note scale.** Stacking every other degree of a 5-note scale does not make a chord (you get shapes like root–tritone–major 7th, or 4 of the 5 scale notes at once). If the melody uses a pentatonic, build the harmony from its 7-note parent mode (pentatonic major → major, pentatonic minor → aeolian/dorian) and keep chord roots on notes the melody can use.
- **Every chord is a real chord.** Check each progression in each scale the engine can pick: major or minor triads (plus 7ths/9ths where the genre wants them). No accidental diminished or augmented chords. In harmonic minor use the raised 7th only over V and vii.
- **Voice-lead between chords.** Pick the inversion closest to the previous voicing (target ≲ 7 semitones of total movement per change). Root-position blocks jumping in parallel sound amateur.
- **Negative degrees are real notes.** Convert with floor division: `octave = floorDiv(deg, len)`, `pc = deg - octave * len`. Never `% len`: it folds the melody into one octave and turns "a step below" into "a 6th above".
- **The rest marker is never `-1`.** Cell maths (approach note `cellDeg[0] - 1`, inversions, leaps of -1/-2) produces -1 all the time; using it as "rest" silently deletes those notes. Use a sentinel like `-99 => int REST`.
- **Transpose phrases as a whole** by the chord's offset (nearest octave of the chord root), not note by note with a wrap.

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
- **Notes on strong beats are chord tones** (snap the cell note to the nearest chord tone when it lands on beat 1 or 3 or is held). Non-chord tones are short and stepwise (≤ 2 semitones), never a held semitone against the pad.
- Reject degenerate cells (all the same note, or a neighbour wobble whose retrograde is identical): they make the variations inaudible.

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
- Bar 4 bass simplifies — just roots, resolving (a walk-up into the next chord's root works well)
- **Bass is audible and has space**: fundamental roughly 40-120 Hz (about MIDI 28-47), a note envelope, and gaps. A sine at 16-30 Hz is inaudible on most speakers; an unenveloped bass is a drone.
- **Bass and kick don't fight**: in four-on-the-floor genres the bass avoids kick steps (offbeat techno bass, the goa kick-bass roll) or ducks under the kick.
- The listener hears bass and lead as parts of the same piece because they share the same intervals

### 9. Arrangement mask — not everything plays all the time
A track where every layer loops from bar 1 sounds like a tech demo. Real music has **structure** — layers enter, exit, and interact across the phrase.
- Generate an `arrangement[16]` array in `generateMotif()` — one entry per bar of the 16-bar phrase
- Levels: `0` = minimal, `1` = bass, `2` = bass + pad/keys, `3` = bass + pad + lead
- **Templates move in 4-bar blocks aligned with the motif** (bars 0, 4, 8, 12), so a lead section always starts at motif bar 1. A window like bars 2-3 only plays the second half of the motif and the listener never hears the cell itself.
- Seed selects from arrangement templates:
  - **Build**: bass only → +pad → +lead → strip back (1,1,1,1, 2,2,2,2, 3,3,3,3, 2,2,2,2)
  - **Call-response**: lead blocks alternate with bass-only blocks (1,1,1,1, 3,3,3,3, 2,2,2,2, 3,3,3,3)
  - **Full-then-strip**: everything up front, then layers drop (3,3,3,3, 3,3,3,3, 2,2,2,2, 1,1,2,2)
- **Rotate the template per pass**: `(seed + phraseRepeat) % templates`, so successive 16-bar passes differ
- In the sequencer, read `arrangement[phraseBar]` and only trigger layers at or above the current level
- When a layer is gated off, fade its target to 0 — don't hard-cut

### 10. Pad/keys dynamics follow the phrase
Static pad = lifeless drone. The pad should breathe with the harmonic rhythm:
- Bars 1-2 of each chord: gentle (≈ 1× the layer's base level)
- Bar 3: peak (≈ 2×) — this is where the phrase builds
- Bar 4: pull back (≈ 0.7×) — creates space before the next chord
- These are ratios, not absolute gains: what a given gain sounds like depends on the oscillators behind it. Set the base level by measuring the layer against the kick (see "Verifying without listening").
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
- **Tension**: whole-half diminished, chromatic clusters — as colour for a passage, never as the scale for a whole track (minutes of diminished triads)
- Let seed/mood determine which pool to draw from
- Avoid incomplete "scales" like `[0,2,4,5,7]` (no 6th or 7th, a semitone at the top): they clash far more than a real mode and give no usable chords

### 14. Occasional FX for tension and release
A track that never changes its effects sounds static. Occasional FX moments give it the dynamics of a DJ turning knobs:
- **When**: ~40% chance at bar 12 of each 16-bar phrase (gives 4 bars of buildup before phrase reset). Only triggers at energy >= 2 and not during transitions.
- **Seed-deterministic**: `(seed * 7 + stepCount / 320) % 5` — same seed gets same FX pattern but varies over time.
- **Three FX types** (seed selects which):
  1. **HPF sweep**: Master bus high-pass filter sweeps up, thinning the mix. Genre ranges: lofi 800Hz, techno 2000Hz, DnB 1500Hz, dub 600Hz, ambient 400Hz. Uses quadratic curve (`p * p`) for natural acceleration.
  2. **Reverb wash**: Boosts reverb mix gain and feedback. Everything gets spacious and washy. Reverb returns to base values via smooth decay when FX ends.
  3. **Third FX** (genre-specific): Delay feedback swell (lofi/DnB/techno), dub delay throw swell (dub), or shimmer boost (ambient).
- **Release**: When the FX ends, parameters don't snap back — they smooth-decay toward base values (0.95 * current + 0.05 * base per bar for reverb/delay, substep smoothing for HPF).
- **Filter changes always glide.** Set a target and move the cutoff toward it every substep; jumping the HPF once per bar caused full-scale clipping in DnB.
- **Gain staging**: master peak at or below about -3 dBFS in every energy level and FX. A `Dyno` limiter after `fxHPF` is a reasonable safety net, not a substitute for sane levels.
- **Signal chain**: All engines route through `Gain masterOut => HPF fxHPF => dac` with the HPF normally at 20Hz (transparent). Both dry and reverb outputs feed `masterOut`.

### 15. Motif variation across repetitions
The same 4-bar motif repeating identically sounds like a loop, not a performance. Each repetition within the 16-bar phrase gets subtle changes:
- **Rep 0** (bars 0-3): Play motif as written — establish the idea
- **Rep 1** (bars 4-7): Drop one note (`(seed + phraseStep) % 5 == 0` → set deg to `REST`) — creates a "question" feel. Never drop the final resolution note.
- **Rep 2** (bars 8-11): Octave jump on the bar 3 peak note only — jumping every bar-3 note gives 14-15 semitone leaps
- **Rep 3** (bars 12-15): Approach note from below on selected steps (`deg - 1`) — resolution with ornamentation
- Applied in the lead playback section, not in `generateMotif()` — the motif array stays clean, variations are applied on read
- Make the choice of dropped/ornamented notes depend on `phraseRepeat` too, so each 16-bar pass is not identical to the last

### 16. Chord substitutions
Repeating the same 4 chords forever becomes wallpaper. Every 3rd cycle of the 16-bar phrase (`phraseRepeat % 3 == 2`), substitute one chord:
- `(seed * 13 + phraseRepeat) % 4` picks which chord to replace
- Genre-specific substitution flavor: lofi = up a 3rd (jazz tritone-ish), techno = up 2 degrees (modal interchange), DnB = up 1 degree (chromatic approach), dub = up 3 degrees (up a 4th), ambient = up 5 degrees (deceptive resolution)
- Degree offsets assume a 7-note harmony scale (see 3b); on a 5-note scale "up 5" is the same chord an octave up. The result must be a real chord: skip the substitution if it lands on a diminished or augmented one.
- Applied via `chordSub[4]` array (-1 = no sub) checked after reading `progs[progIdx][chordIdx]`
- Reset on new state events and at each phrase boundary

### 17. Drum micro-variation
Static drum patterns are the #1 giveaway of machine-generated music. Add seed-deterministic per-bar mutations:
- `(seed + phraseBar * 7) % 8` gives a variation value per bar
- Low values: add a ghost hat on an empty step; high values: add a ghost snare
- Only at energy >= 2 (don't vary minimal patterns)
- Genre-specific step positions: lofi = steps 5/11, techno = steps 3/7, DnB = steps 7/9, dub = steps 5/9; goa and reggae: choose steps that avoid the kick and the skank
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

### 20. Genre exceptions
The principles above are written for groove genres. Where they don't fit:
- **Piano** (solo): no swing, drum fills, FX sweeps or intro HPF (7, 7b, 14, 17 don't apply). One chord per bar at 60 BPM; detune ~2 cents, not ±0.3% (that sounds honky-tonk); damp sounding notes at chord changes like a sustain pedal; left-hand pattern changes with energy.
- **Ambient**: no drums. The reverb needs a long tail (RT60 several seconds), outside the 0.3-0.45 feedback range of principle 2. Drones and pads must retune with the chord quickly enough to arrive (a glide that takes longer than the chord is permanently out of tune).

### 21. ChucK gotchas
- A function that reads a global declared **later** in the file compiles fine and crashes at runtime. Declare globals before any function that uses them.
- `/` on ints is integer division and `%` keeps the sign of the dividend: write a `floorDiv` helper for degree maths (3b).
- `Std.atoi` is **32-bit**: `Std.atoi("1794570052276")` gives `-726277452`. Anything an engine parses (the state file's timestamp included) must stay below 2^31; writers keep the timestamp in 1..1e9.
- `--silent` runs faster than real time: good for analysis, but time-based behaviour (decay, idle fade) happens in seconds of wall time.

### 22. Verifying without listening
Ears are the final test, but most of the bugs above are measurable. Log every note event from a copy of the engine (bar, step, instrument, MIDI note, velocity, chord root) and render stems with `dac => WvOut2 w => blackhole` running alongside under `--silent`. Check, across several seeds and every scale:
- Strong-beat lead and bass notes on chord tones: ≥ 85%
- Held semitone/tritone clashes between layers: < 10%
- Melodic leaps wider than a 5th: < 15%
- Distinct 4-bar lead windows over 5 minutes: more than a handful (not 1-2), but the cell still recognisable
- Each layer audible: nothing important more than ~25 dB below the kick; bass energy not concentrated below 40 Hz
- Master peak ≤ -3 dBFS, no clipped samples

### 13. State file interface
Engines are started as `chuck genres/<genre>.ck:<run dir>` (see `lib/paths.sh`; without the argument they fall back to the legacy `/tmp/beatpilot-*` files). They read `<run dir>/state`:
```
energy (0-3)
key (0-11)
scale (index)
seed (0-255)
timestamp (a positive integer below 2^31 that changes per write)
```
Read once per bar (step 0):
- **Energy** acts on every new timestamp.
- **Tune** (key/scale/seed) is applied only when it differs from the current one, and only at the phrase boundary (`phraseBar == 15` before the advance), or at once when silent. The re-seed sets `phraseBar` to -1 so the advance lands on bar 0. `Math.srandom()` is seeded from the tune so the same events give the same music.
- `<run dir>/volume` (0-100) is read each bar.

Each bar (step 1) engines write `<run dir>/now` for the Claude Code player: `genre bpm tick energy key seed scale prog chord bar level arr playing volume`, one `name value` per line, ending with `end`. Every engine needs `writeNow()` and the quantized tune block; keep both when editing `readState()`.

## Adding a New Genre

1. Copy the closest existing engine as a starting point (it brings the state reader, the phrase-quantized tune change and `writeNow()`), and add the genre to `BEATPILOT_GENRES` in `lib/paths.sh`, `GENRES` in `hooks/music.ts` and the `genre` options in `.claude-plugin/plugin.json`
2. Set BPM and swing amount appropriate to genre
3. Define drum patterns (4 energy levels × 16 steps) + ghost patterns
4. Define chord progressions (at least 4, mix of moods)
5. Define scales appropriate to genre, and check every progression in every scale gives real chords (3b)
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
20. Measure it (principle 22): chord tones, clashes, leaps, variety, levels, clipping
21. Listen: does it sound like a composed piece or a tech demo? Check:
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
# write-state.sh <energy 0-3> [content | - | --keep]
/path/to/beatpilot/adapters/write-state.sh 2 "add a login page"   # new task: new tune
/path/to/beatpilot/adapters/write-state.sh 3 --keep               # energy only, same tune
```

This is the building block for writing your own adapter for any tool.

## Adapter Architecture

```
adapters/
  write-state.sh    — shared core: hashes content → key/scale/seed, writes state
  claude-code.sh    — Claude Code adapter (receives hook JSON on stdin)
  copilot-cli.sh    — GitHub Copilot CLI adapter (receives hook JSON on stdin)
  filewatcher.sh    — universal adapter (watches filesystem for changes)
hook.sh             — thin wrapper → adapters/claude-code.sh (./install.sh route)
hooks/register.tsx  — the Claude Code plugin's in-process mod (events, engine, player)
```

All adapters call `write-state.sh`, which handles:
- MD5 hashing of content into musical parameters (key, scale, seed)
- Atomic state file writes to `<run dir>/state` (a private per-user directory, see `lib/paths.sh`)
- Auto-starting the ChucK engine if not running

## File Structure
- `genres/*.ck` — genre engines (one per genre)
- `adapters/` — client adapters (Claude Code, file watcher, write-state core)
- `hook.sh` — Claude Code hook entry point (forwards to adapter)
- `start.sh` / `stop.sh` / `toggle.sh` — engine lifecycle
- `vibe.sh` — genre switcher
- `volume.sh` — volume control (0-100)
- `skills/` — Claude Code slash commands (`/beatpilot:music`, `/beatpilot:vibe`, `/beatpilot:volume`)
