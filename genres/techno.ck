// engine.ck - Beatpilot Techno Engine
// A continuous techno groove that evolves based on Claude hook events.
// Reads state from /tmp/beatpilot-state (written by hook.sh).
// Energy (0-3) controls which layers are active and pattern intensity.
// Transitions: drops, risers, fills, and breakdowns triggered by events.

// ============ SAMPLE DETECTION ============
me.dir() + "/../samples/techno/" => string smpDir;
0 => int useSamples;

// ============ CLOCK ============
128.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;
4 => int SUBSTEPS;
0.62 => float swingAmt; // 0.5 = straight, 0.67 = heavy shuffle, 0.62 = nice groove

// ============ STATE ============
0 => int energy;
0 => int key;
0 => int scaleType;
0 => int seed;
0 => int lastEventTs;
0 => int stepCount;
0 => int barsSinceEvent;
0.0 => float masterGain;
0.0 => float masterTarget;
0.8 => float volume;
0 => int variant;
0 => int drumFill;

// ============ FX STATE (occasional tension/release) ============
0 => int fxType;  // 0=none, 1=hpf_sweep, 2=reverb_wash, 3=delay_swell
0 => int fxBar;
0 => int fxLen;

// ============ INTRO STATE (call to the dancefloor) ============
0 => int introActive;
0 => int introBar;
0 => int introLen;

// ============ PHRASE / SONG STRUCTURE ============
// Chord progression: 4 chords, each lasts 4 bars = 16-bar phrase
// Progressions are arrays of root scale degrees
[[0, 3, 4, 2], [0, 4, 3, 1], [0, 2, 3, 4], [0, 1, 3, 2]] @=> int progs[][];
0 => int progIdx;       // which progression (set by seed)
0 => int chordIdx;      // current chord in progression (0-3)
0 => int chordRoot;     // current chord root degree
0 => int phraseBar;     // bar within 16-bar phrase (0-15)
0 => int phraseRepeat;
int chordSub[4];

// Lead motif: 4-bar phrase (64 steps) with melodic contour
// Bar 1: call (short figure), Bar 2: response (variation),
// Bar 3: development (higher/busier), Bar 4: resolution (back to root)
64 => int PHRASE_LEN;
int motif[64];          // lead: scale degrees per step (-1 = rest)
int bassLine[64];       // bass: scale degrees per step (-1 = rest)
0 => int motifGenerated;
0 => int phraseStep;    // current position in the 64-step phrase

// Arrangement mask: which bars (0-15) have which layers active
// This gives the track structure — not everything plays all the time
// 0=nothing, 1=bass only, 2=bass+pad, 3=bass+pad+lead
int arrangement[16];

fun void generateMotif() {
    seed => int s;
    for(0 => int i; i < PHRASE_LEN; i++) -1 => motif[i];

    // --- CELL-BASED COMPOSITION ---
    // Techno: denser than lofi, more repetitive/hypnotic

    int cellDeg[3];
    int cellPos[3];

    0 => cellDeg[0];
    [1, 2, -1, 2, 1, -2] @=> int leaps[];
    leaps[s % leaps.cap()] => int leap1;
    leap1 => cellDeg[1];
    [-1, 0, 1, -1, 0] @=> int resolves[];
    cellDeg[1] + resolves[(s / 2) % resolves.cap()] => cellDeg[2];

    // Techno cell rhythm: tighter, more driving
    [[0, 2, 4], [0, 4, 6], [0, 2, 6], [2, 4, 6], [0, 4, 8]] @=> int cellRhythms[][];
    cellRhythms[(s / 3) % cellRhythms.cap()] @=> int cR[];
    cR[0] => cellPos[0]; cR[1] => cellPos[1]; cR[2] => cellPos[2];

    s % 3 => int varType;

    // Bar 1: cell
    for(0 => int i; i < 3; i++) cellDeg[i] => motif[cellPos[i]];

    // Bar 2: cell varied
    if(varType == 0) {
        for(0 => int i; i < 3; i++) cellDeg[i] + 2 => motif[16 + cellPos[i]];
    } else if(varType == 1) {
        cellDeg[0] => motif[16 + cellPos[0]];
        cellDeg[0] - leap1 => motif[16 + cellPos[1]];
        cellDeg[0] - leap1 - resolves[(s / 2) % resolves.cap()] => motif[16 + cellPos[2]];
    } else {
        for(0 => int i; i < 3; i++) cellDeg[2 - i] + 1 => motif[16 + cellPos[i]];
    }

    // Bar 3: cell twice — first transposed, then original with approach
    for(0 => int i; i < 3; i++) cellDeg[i] + 3 => motif[32 + cellPos[i]];
    cellDeg[0] - 1 => motif[32 + 8];
    for(0 => int i; i < 3; i++) cellDeg[i] => motif[32 + 10 + i * 2];

    // Bar 4: half cell + resolve
    cellDeg[0] + 1 => motif[48];
    cellDeg[1] => motif[52];
    0 => motif[60];

    // --- BASS LINE: derived from the same cell ---
    // Bass plays the cell's root notes on strong beats, with the cell's
    // first interval as a passing tone. Simpler, anchoring the harmony.
    for(0 => int i; i < PHRASE_LEN; i++) -1 => bassLine[i];

    // Bar 1: root on 1, cell interval on the &
    0 => bassLine[0];
    cellDeg[1] => bassLine[6];
    0 => bassLine[8];

    // Bar 2: same rhythm, transposed with the cell variation
    if(varType == 0) {
        2 => bassLine[16]; cellDeg[1] + 2 => bassLine[22]; 2 => bassLine[24];
    } else if(varType == 1) {
        0 => bassLine[16]; 0 - leap1 => bassLine[22]; 0 => bassLine[24];
    } else {
        1 => bassLine[16]; cellDeg[2] + 1 => bassLine[22]; 1 => bassLine[24];
    }

    // Bar 3: busier — follows lead rhythm but stays on roots + passing tones
    0 => bassLine[32]; cellDeg[1] => bassLine[34];
    3 => bassLine[36]; cellDeg[1] + 3 => bassLine[38];
    0 => bassLine[40]; cellDeg[2] => bassLine[44];

    // Bar 4: simple — root, then rest until the resolve
    0 => bassLine[48];
    0 => bassLine[56];

    // --- ARRANGEMENT: which bars have which layers ---
    // 16-bar phrase with structure, not everything all the time
    // Seed varies the arrangement shape
    s % 3 => int arrType;
    if(arrType == 0) {
        // Build: bass → +pad → +lead → strip
        [1,1,1,1, 2,2,2,2, 3,3,3,3, 2,2,1,1] @=> int arrA[];
        for(0 => int i; i < 16; i++) arrA[i] => arrangement[i];
    } else if(arrType == 1) {
        // Call-response: lead bars alternate with bass-only bars
        [1,1,3,3, 1,1,3,3, 2,2,3,3, 3,3,2,1] @=> int arrB[];
        for(0 => int i; i < 16; i++) arrB[i] => arrangement[i];
    } else {
        // Full then strip: everything then breakdown
        [2,2,3,3, 3,3,3,3, 2,2,2,2, 1,1,2,2] @=> int arrC[];
        for(0 => int i; i < 16; i++) arrC[i] => arrangement[i];
    }

    0 => phraseStep;
    1 => motifGenerated;
}

// ============ TRANSITION STATE ============
// 0=none, 1=riser (building), 2=drop (kick out, tension), 3=impact (kick back hard)
0 => int transition;
0 => int transitionBars;   // bars remaining in current transition
0 => int transitionStep;   // steps into transition
0 => int lastTransitionTs; // prevent overlapping transitions

// ============ AUTO-EVOLUTION (idle sections) ============
// When Claude is working on a long task, cycle through musical sections
// instead of just decaying to silence.
// Sections: 0=normal, 1=breakdown (strip to pad+hats), 2=ambient (pad only, half-feel),
//           3=build (riser + hats intensify), 4=drop (everything slams back)
0 => int autoSection;
0 => int autoSectionBar;   // bars into current auto section
0 => int autoActive;       // whether auto-evolution is running
// Section durations in bars
[0, 8, 6, 4, 1] @=> int autoSectionLen[];
// Cycle order
[1, 2, 3, 4, 0] @=> int autoNextSection[];

// ============ MASTER BUS ============
Gain masterOut => HPF fxHPF => dac;
20.0 => fxHPF.freq; 0.8 => fxHPF.Q;
Gain master => masterOut;
0.0 => master.gain;

// ============ SAMPLE BUFFERS ============
SndBuf smpKick => Gain smpKickG => master;
SndBuf smpSnare => Gain smpSnareG => master;
SndBuf smpClap => Gain smpClapG => master;
SndBuf smpHat => Gain smpHatG => master;
SndBuf smpHatOpen => Gain smpHatOpenG => master;
0.0 => smpKickG.gain; 0.0 => smpSnareG.gain; 0.0 => smpClapG.gain;
0.0 => smpHatG.gain; 0.0 => smpHatOpenG.gain;

FileIO smpTest;
if(smpTest.open(smpDir + "kick.wav", FileIO.READ)) {
    smpTest.close();
    smpKick.read(smpDir + "kick.wav");
    smpSnare.read(smpDir + "snare.wav");
    smpClap.read(smpDir + "clap.wav");
    smpHat.read(smpDir + "hat_closed.wav");
    smpHatOpen.read(smpDir + "hat_open.wav");
    smpKick.samples() => smpKick.pos;
    smpSnare.samples() => smpSnare.pos;
    smpClap.samples() => smpClap.pos;
    smpHat.samples() => smpHat.pos;
    smpHatOpen.samples() => smpHatOpen.pos;
    1 => useSamples;
    <<< "Beatpilot [techno]: samples loaded" >>>;
} else {
    <<< "Beatpilot [techno]: no samples found, using synthesis" >>>;
}

// ============ SCALES ============
[[0,2,4,7,9], [0,3,5,7,10], [0,2,4,5,7], [0,2,3,7,10]] @=> int scales[][];

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    if(degree < 0) return 0;
    return key + octave * 12 + scl[degree % scl.cap()] + (degree / scl.cap()) * 12;
}

// ============ KICK ============
SinOsc kickOsc => LPF kickLPF => Gain kickG => master;
0.0 => kickOsc.gain;
300.0 => kickLPF.freq;
0.35 => kickG.gain;
0.0 => float kickPh;
// Click transient for punch
Noise kickClick => BPF kickClickBP => ADSR kickClickEnv => kickG;
3500.0 => kickClickBP.freq; 1.5 => kickClickBP.Q;
kickClickEnv.set(0.2::ms, 8::ms, 0.0, 3::ms);
0.3 => kickClick.gain;

[[1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,1,0]] @=> int kPat[][];

// ============ VELOCITY MAPS ============
// Hat velocity: accents on beats, ghost notes on off-beats (0.0-1.0)
[1.0, 0.3, 0.7, 0.3, 1.0, 0.3, 0.7, 0.4, 1.0, 0.3, 0.7, 0.3, 1.0, 0.35, 0.7, 0.5] @=> float hatVel[];
// Kick velocity: beat 1 hardest, slight variation
[1.0, 0.0, 0.0, 0.0, 0.9, 0.0, 0.0, 0.0, 0.95, 0.0, 0.0, 0.0, 0.85, 0.0, 0.8, 0.0] @=> float kickVel[];

// ============ CLOSED HAT ============
Noise chN => HPF chHP => ADSR chEnv => Gain chG => master;
8000.0 => chHP.freq;
chEnv.set(0.3::ms, 22::ms, 0.0, 5::ms);
0.07 => chG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0]] @=> int chPat[][];

// ============ OPEN HAT ============
Noise ohN => BPF ohBP => ADSR ohEnv => Gain ohG => master;
9000.0 => ohBP.freq; 1.5 => ohBP.Q;
ohEnv.set(1::ms, 150::ms, 0.03, 100::ms);
0.05 => ohG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
 [0,0,0,0,0,0,0,1,0,0,0,1,0,0,1,0]] @=> int ohPat[][];

// ============ BASS ============
TriOsc bassOsc => LPF bassF => Gain bassG => master;
0.6 => bassOsc.gain;
200.0 => bassF.freq; 4.0 => bassF.Q;
0.12 => bassG.gain;
200.0 => float bassFiltTarget;

[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1,-1,-1, 0,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1, 0,-1,-1, 3,-1, 0,-1,-1,-1,-1, 4, 0,-1],
 [ 0,-1, 5,-1, 0,-1,-1, 3, 0,-1,-1, 7, 0,-1, 5,-1]] @=> int bPatA[][];

[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1, 0,-1,-1,-1,-1,-1, 0,-1,-1,-1],
 [ 0,-1, 0,-1,-1, 4,-1,-1,-1, 0,-1,-1, 3,-1,-1, 0],
 [ 0, 5,-1, 0,-1, 3,-1, 7,-1, 0,-1, 5, 0,-1, 3,-1]] @=> int bPatB[][];

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [1,0,0,1,0,0,1,0,1,0,0,0,0,1,0,0],
 [1,0,1,0,1,0,0,1,1,0,0,1,0,1,0,1]] @=> int bAcc[][];

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0],
 [0,0,1,0,0,0,0,0,0,0,0,1,0,0,1,0]] @=> int bOctUp[][];

// ============ LEAD ============
// Sine fundamental + quiet octave harmonic = clean, bell-like tone
SinOsc ldOsc1 => LPF ldF => Gain ldDry => master;
SinOsc ldOsc2 => ldF;  // octave up, quieter
0.5 => ldOsc1.gain; 0.18 => ldOsc2.gain;
2800.0 => ldF.freq; 0.8 => ldF.Q; // gentle roll-off, not aggressive
0.0 => ldDry.gain;
2800.0 => float ldFiltTarget;
0.0 => float ldAmpTarget;
0.0 => float ldAmpCurrent;
-1 => int lastLeadDeg;

// Lead delay: dotted-eighth feedback delay for rhythmic echoes
ldDry => Delay ldDly1 => Gain ldDlyFb => LPF ldDlyF => master;
ldDlyFb => ldDly1; // feedback loop
(stepDur * 3) => ldDly1.max => ldDly1.delay; // dotted eighth = 3 steps
0.45 => ldDlyFb.gain;   // feedback amount — decays over ~3 repeats
0.04 => ldDly1.gain;    // wet level
2500.0 => ldDlyF.freq;  // darken repeats

// ============ PAD ============
TriOsc padOsc1 => LPF padF => Gain padG => master;
SinOsc padOsc2 => padF;
TriOsc padOsc3 => padF;
0.25 => padOsc1.gain; 0.3 => padOsc2.gain; 0.2 => padOsc3.gain;
400.0 => padF.freq; 1.8 => padF.Q;
0.0 => padG.gain;
0.0 => float padGainTarget;
400.0 => float padFiltTarget;
0 => int padLastDeg;
0.0 => float padLfoPhase;

// ============ CLAP ============
Noise clpN => BPF clpBP => ADSR clpEnv => Gain clpG => master;
1200.0 => clpBP.freq; 2.0 => clpBP.Q;
clpEnv.set(0.5::ms, 60::ms, 0.0, 20::ms);
0.0 => clpG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0]] @=> int clpPat[][];

// ============ RISER / FX ============
Noise riserN => BPF riserBP => Gain riserG => master;
500.0 => riserBP.freq; 4.0 => riserBP.Q;
0.0 => riserG.gain;
500.0 => float riserFreqTarget;

// Impact: big low sine hit for drop moments
SinOsc impactOsc => Gain impactG => master;
0.0 => impactOsc.gain;
0.0 => impactG.gain;

// ============ STATE FILE READER ============
fun void readState() {
    FileIO f;
    if(f.open("/tmp/beatpilot-state", FileIO.READ)) {
        Std.atoi(f.readLine()) => int newEnergy;
        Std.atoi(f.readLine()) => int newKey;
        Std.atoi(f.readLine()) => int newScale;
        Std.atoi(f.readLine()) => int newSeed;
        Std.atoi(f.readLine()) => int newTs;
        f.close();

        if(newTs != lastEventTs && newTs > 0) {
            newTs => lastEventTs;
            newKey % 12 => key;
            newScale % 4 => scaleType;
            newSeed % 256 => seed;
            newSeed % 2 => variant;
            seed % progs.cap() => progIdx;
            0 => phraseBar;
            0 => chordIdx;
            0 => phraseRepeat;
            for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
            progs[progIdx][0] => chordRoot;
            generateMotif();

            // --- TRANSITION TRIGGERS ---
            // Only trigger if not already in a transition
            if(transition == 0 && energy >= 1) {
                if(newEnergy >= 3 && energy < 3) {
                    // Big moment: riser → drop → impact
                    2 => transition;
                    3 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy >= 2 && newEnergy > energy) {
                    // Medium: short riser into drop
                    2 => transition;
                    2 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy == 0) {
                    // Error/breakdown: immediate strip
                    4 => transition;
                    2 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy < energy && energy >= 2) {
                    // Winding down: filter sweep breakdown
                    4 => transition;
                    1 => transitionBars;
                    0 => transitionStep;
                }
            }

            newEnergy => energy;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;

            // Coming back from silence? Classic techno filtered intro
            if(masterTarget < 0.01 && newEnergy >= 2) {
                if((seed + newSeed) % 2 == 0) {
                    1 => introActive;
                    0 => introBar;
                    if((seed * 3 + newSeed) % 2 == 0) 2 => introLen;
                    else 4 => introLen;
                    2500.0 => fxHPF.freq;
                }
            }

            1.0 => masterTarget;

            // Cancel auto-evolution — real event takes over
            if(autoActive) {
                0 => autoActive;
                0 => autoSection;
                0 => autoSectionBar;
            }

            if(energy >= 2) {
                0.09 => ldDry.gain;
                0.08 => clpG.gain;
            } else {
                0.0 => ldAmpTarget;
                0.0 => clpG.gain;
            }
        }
    }
}

// ============ MAIN SEQUENCER ============
while(true) {
    stepCount % 16 => int s;

    // ---- BAR BOUNDARY ----
    if(s == 0) {
        readState();
        // Read volume
        FileIO vf;
        if(vf.open("/tmp/beatpilot-volume", FileIO.READ)) {
            Std.atoi(vf.readLine()) => int vol;
            vf.close();
            if(vol >= 0 && vol <= 100) vol / 100.0 => volume;
        }
        barsSinceEvent + 1 => barsSinceEvent;

        // Transition bar countdown
        if(transition > 0) {
            transitionBars - 1 => transitionBars;
            if(transitionBars <= 0) {
                // Transition ending — trigger impact if it was a drop
                if(transition == 2) {
                    3 => transition; // switch to impact bar
                    1 => transitionBars;
                } else {
                    0 => transition;
                    0 => riserG.gain;
                }
            }
        }

        // Advance phrase / chord progression
        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) {
            0 => phraseBar;
            phraseRepeat + 1 => phraseRepeat;
            for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
            if(phraseRepeat % 3 == 2 && energy >= 2) {
                (seed * 13 + phraseRepeat) % 4 => int subIdx;
                // Modal interchange: shift chord up 2 degrees
                (progs[progIdx][subIdx] + 2) % 5 => chordSub[subIdx];
            }
            // NEW TRACK: every 4 phrase repeats (~64 bars), evolve into a new track
            if(phraseRepeat % 4 == 0 && phraseRepeat > 0 && energy >= 1 && transition == 0) {
                // New seed = new motif, new feel
                (seed + phraseRepeat * 7 + 43) % 256 => seed;
                seed % progs.cap() => progIdx;
                seed % scales.cap() => scaleType;
                // Shift key by a musically useful interval (4th or 5th)
                (key + 5 + (seed % 2) * 2) % 12 => key;
                progs[progIdx][0] => chordRoot;
                generateMotif();
                // Trigger a breakdown transition for the DJ mix feel
                4 => transition;
                2 => transitionBars;
                0 => transitionStep;
                <<< "Beatpilot [techno]: new track" >>>;
            }
        }
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        progs[progIdx][chordIdx] => chordRoot;
        if(chordSub[chordIdx] >= 0) chordSub[chordIdx] => chordRoot;

        // Energy decay — but trigger auto-evolution instead of silence
        if(barsSinceEvent > 6 && energy > 0 && transition == 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) {
                0.0 => ldAmpTarget;
                0.0 => clpG.gain;
            }
        }

        // Fade out when idle — no auto-evolution, just graceful silence
        if(barsSinceEvent > 10 && energy == 0 && transition == 0) {
            0.0 => masterTarget;
        }

        // Drum fill at phrase boundaries
        0 => drumFill;
        if(energy >= 1 && motifGenerated) {
            if(phraseBar == 15) 2 => drumFill;
            else if(phraseBar % 4 == 3) 1 => drumFill;
        }

        // ---- INTRO: call to the dancefloor ----
        if(introActive) {
            introBar + 1 => introBar;
            if(introBar > introLen) {
                // DROP — full groove lands
                0 => introActive;
                20.0 => fxHPF.freq;
                0.45 => ldDlyFb.gain;
                0.06 => ldDly1.gain;
            } else {
                introBar $ float / introLen $ float => float p;
                // HPF sweeps down: classic techno filter open
                2500.0 * (1.0 - p) * (1.0 - p) + 20.0 => fxHPF.freq;
                // Delay feedback wash during intro
                0.60 => ldDlyFb.gain;
                0.08 => ldDly1.gain;
            }
        }

        // ---- FX: occasional tension/release ----
        if(fxType == 0 && energy >= 2 && motifGenerated && phraseBar == 12 && transition == 0 && !introActive) {
            (seed * 7 + stepCount / 320) % 5 => int fxRoll;
            if(fxRoll <= 2) {
                fxRoll + 1 => fxType;
                0 => fxBar;
                4 => fxLen;
            }
        }
        if(fxType > 0) {
            fxBar + 1 => fxBar;
            if(fxBar > fxLen) {
                0 => fxType; 0 => fxBar;
            } else {
                fxBar $ float / fxLen $ float => float p;
                if(fxType == 1) {
                    // HPF sweep: classic techno riser — sweeps higher than lofi
                    20.0 + p * p * 2000.0 => fxHPF.freq;
                } else if(fxType == 2) {
                    // Pad filter resonance sweep: Q rises, filter sweeps
                    1.8 + p * 6.0 => padF.Q;
                    padFiltTarget + p * 800.0 => padF.freq;
                } else if(fxType == 3) {
                    // Delay feedback swell
                    0.45 + p * 0.30 => ldDlyFb.gain;
                    0.06 + p * 0.04 => ldDly1.gain;
                }
            }
        }
        if(fxType == 0 && !introActive) {
            if(padF.Q() > 1.9) padF.Q() * 0.92 + 1.8 * 0.08 => padF.Q;
            if(ldDlyFb.gain() > 0.46) ldDlyFb.gain() * 0.95 + 0.45 * 0.05 => ldDlyFb.gain;
            if(ldDly1.gain() > 0.065) ldDly1.gain() * 0.93 + 0.06 * 0.07 => ldDly1.gain;
        }
    }

    // ---- TRANSITION FX ----
    transitionStep + 1 => transitionStep;

    0 => int kickMuted;
    0 => int hatFill;


    if(transition == 2) {
        // DROP: kill kick, riser sweeps up, hats do fill in last bar
        1 => kickMuted;
        // Riser noise sweep: freq rises over the transition
        0.07 + transitionStep * 0.0005 => float rGain;
        if(rGain > 0.12) 0.12 => rGain;
        rGain => riserG.gain;
        500.0 + transitionStep * 80.0 => riserFreqTarget;
        if(riserFreqTarget > 12000.0) 12000.0 => riserFreqTarget;
        // Hat fill: every step in last 8 steps of transition
        if(transitionBars <= 1 && s >= 8) 1 => hatFill;
    } else if(transition == 3) {
        // IMPACT: kick comes back HARD, riser cuts, big low hit
        0 => transition;
        0 => riserG.gain;
        // Trigger impact boom
        0.5 => impactG.gain;
        50.0 => impactOsc.freq;
        0.9 => impactOsc.gain;
        // Extra hard kick on beat 1
        if(s == 0) {
            0.0 => kickPh;
            1.0 => kickOsc.gain;
            kickClickEnv.keyOn();
        }
    } else if(transition == 4) {
        // BREAKDOWN: filter everything down, thin out
        1 => kickMuted;
        // Sweep bass filter down
        200.0 => bassFiltTarget;
        400.0 => ldFiltTarget;
        0.0 => ldAmpTarget;
    }

    // ---- KICK (with velocity + humanization) ----
    if(!kickMuted && kPat[energy][s]) {
        0.0 => kickPh;
        ((seed * 17 + stepCount) % 100 - 50) / 1000.0 => float velDrift;
        0.5 + 0.5 * (kickVel[s] + velDrift) => float kVel;
        if(useSamples) {
            0 => smpKick.pos;
            kVel * 0.10 => smpKickG.gain;
        }
        kVel * 0.8 => kickOsc.gain;
        kVel * 0.3 => kickClick.gain;
        if(useSamples) { kickOsc.gain() * 0.3 => kickOsc.gain; kickClick.gain() * 0.3 => kickClick.gain; }
        kickClickEnv.keyOn();
    }

    // ---- HATS (with velocity) ----
    if(hatFill) {
        (s $ float) / 16.0 => float fillVel;
        if(useSamples) { 0 => smpHat.pos; 0.08 + 0.10 * fillVel => smpHatG.gain; }
        0.03 + 0.07 * fillVel => chG.gain;
        if(useSamples) chG.gain() * 0.3 => chG.gain;
        chEnv.keyOn();
        if(s % 2 == 0) {
            if(useSamples) { 0 => smpHatOpen.pos; 0.08 => smpHatOpenG.gain; }
            ohEnv.keyOn();
        }
    } else {
        if(chPat[energy][s]) {
            if(useSamples) { 0 => smpHat.pos; 0.08 + 0.10 * hatVel[s] => smpHatG.gain; }
            0.03 + 0.06 * hatVel[s] => chG.gain;
            if(useSamples) chG.gain() * 0.3 => chG.gain;
            chEnv.keyOn();
        }
        if(ohPat[energy][s]) {
            if(useSamples) { 0 => smpHatOpen.pos; 0.06 + 0.08 * hatVel[s] => smpHatOpenG.gain; }
            0.03 + 0.04 * hatVel[s] => ohG.gain;
            if(useSamples) ohG.gain() * 0.3 => ohG.gain;
            ohEnv.keyOn();
        }
    }

    // ---- CLAP ----
    if(clpPat[energy][s]) {
        if(useSamples) { 0 => smpClap.pos; 0.15 => smpClapG.gain; }
        clpEnv.keyOn();
    }

    // ---- DRUM MICRO-VARIATION ----
    if(energy >= 2) {
        (seed + phraseBar * 7) % 8 => int drumVar;
        if(drumVar < 3 && s == 7 && !chPat[energy][s]) {
            0.02 => chG.gain;
            chEnv.keyOn();
        }
        if(drumVar >= 6 && s == 3 && !ohPat[energy][s]) {
            0.015 => ohG.gain;
            ohEnv.keyOn();
        }
    }

    // ---- DRUM FILL (builds at phrase boundaries) ----
    if(drumFill > 0 && energy >= 1) {
        if(drumFill == 2) {
            // Big fill (end of 16-bar phrase): hat + clap roll builds through bar
            if(s >= 2 && !chPat[energy][s]) {
                0.03 + (s $ float) / 16.0 * 0.06 => chG.gain;
                chEnv.keyOn();
            }
            if(s >= 8 && s % 2 == 0) {
                0.04 + (s $ float) / 16.0 * 0.04 => clpG.gain;
                clpEnv.keyOn();
            }
            if(s >= 12) {
                0.03 + (s - 12) / 4.0 * 0.04 => ohG.gain;
                ohEnv.keyOn();
            }
        } else {
            // Small fill (end of 4-bar chord): hat flurry in last quarter
            if(s >= 12 && !chPat[energy][s]) {
                0.04 + (s - 12) / 4.0 * 0.05 => chG.gain;
                chEnv.keyOn();
            }
            if(s == 14) {
                clpEnv.keyOn();
            }
        }
    }

    // ---- ARRANGEMENT: determine what plays this bar ----
    0 => int arrLevel;
    if(motifGenerated) arrangement[phraseBar] => arrLevel;
    if(energy < 2) { if(arrLevel > 1) 1 => arrLevel; }

    // ---- BASS (cell-derived, follows arrangement) ----
    if(transition != 4 && energy >= 1 && arrLevel >= 1 && motifGenerated) {
        bassLine[phraseStep % PHRASE_LEN] => int bDeg;
        if(bDeg >= 0) {
            (bDeg + chordRoot) % 5 => bDeg;
            if(bDeg < 0) bDeg + 5 => bDeg;
            2 => int bassOct;
            // Octave jump on bar 3 passing tones
            if(phraseStep >= 32 && phraseStep < 48 && phraseStep % 2 != 0) 3 => bassOct;
            Std.mtof(note(bDeg, bassOct)) => bassOsc.freq;
            // Filter follows phrase energy: opens up in bar 3
            if(phraseStep >= 32 && phraseStep < 48) {
                1500.0 + Math.random2f(0.0, 1000.0) => bassFiltTarget;
            } else {
                600.0 + Math.random2f(0.0, 600.0) => bassFiltTarget;
            }
        }
    }

    // ---- PAD (follows arrangement + phrase dynamics) ----
    if(transition != 4 && s == 0 && arrLevel >= 2) {
        chordRoot => int pRoot;
        chordRoot + 2 => int pDeg2;
        chordRoot + 4 => int pDeg3;
        Std.mtof(note(pRoot, 4)) => padOsc1.freq;
        Std.mtof(note(pDeg2, 4)) => padOsc2.freq;
        Std.mtof(note(pDeg3, 4)) => padOsc3.freq;
        padOsc1.freq() * 0.998 => padOsc1.freq;
        padOsc3.freq() * 1.002 => padOsc3.freq;
        // Pad dynamics follow phrase position: swell bars 1-3, pull back bar 4
        phraseBar % 4 => int barInChord;
        if(barInChord < 2) 0.04 => padGainTarget;       // bars 1-2: gentle
        else if(barInChord == 2) 0.08 => padGainTarget;  // bar 3: peak
        else 0.03 => padGainTarget;                       // bar 4: pull back
        if(energy >= 3) padGainTarget * 1.3 => padGainTarget;
        600.0 + barInChord * 150.0 => padFiltTarget;     // filter opens through phrase
    } else if(arrLevel < 2) {
        0.0 => padGainTarget;
    }

    // ---- LEAD (cell motif, follows arrangement) ----
    if(transition != 4 && motifGenerated && arrLevel >= 3) {
        motif[phraseStep % PHRASE_LEN] => int deg;
        // Motif variation per repetition
        phraseBar / 4 => int motifRep;
        if(motifRep == 1 && (seed + phraseStep) % 5 == 0) -1 => deg;
        if(motifRep == 3 && deg >= 0 && phraseStep % 8 == 6) deg - 1 => deg;
        if(deg >= 0) {
            (deg + chordRoot) % 5 => deg;
            if(deg < 0) deg + 5 => deg;
            4 => int ldOct;
            if(energy >= 3 && phraseStep >= 32) 5 => ldOct;
            if(motifRep == 2 && phraseStep >= 32 && phraseStep < 48) 5 => ldOct;
            Std.mtof(note(deg, ldOct)) => ldOsc1.freq;
            ldOsc1.freq() * 2.0 => ldOsc2.freq;
            phraseStep % 16 => int localStep;
            0.04 => float ldVel;
            if(localStep % 4 == 0) 0.09 => ldVel;
            else if(localStep % 2 == 0) 0.06 => ldVel;
            if(phraseStep >= 32 && phraseStep < 48) ldVel * 1.2 => ldVel;
            if(phraseStep >= 48) ldVel * 0.75 => ldVel;
            // Filter: vary the sweep shape per repetition so it doesn't always "wah" the same
            if(motifRep == 0) {
                1200.0 + Math.random2f(0.0, 800.0) => ldFiltTarget; // normal sweep
            } else if(motifRep == 1) {
                2800.0 + Math.random2f(0.0, 400.0) => ldFiltTarget; // bright, open — no sweep
            } else if(motifRep == 2) {
                600.0 + Math.random2f(0.0, 400.0) => ldFiltTarget; // dark, muffled
                ldVel * 1.3 => ldVel; // louder to compensate
            } else {
                1800.0 + localStep * 80.0 => ldFiltTarget; // staircase — opens through the bar
            }
            ldVel => ldAmpTarget;
        }
    } else if(arrLevel < 3) {
        0.0 => ldAmpTarget;
    }

    // Advance phrase step (shared by bass + lead)
    if(motifGenerated) {
        phraseStep + 1 => phraseStep;
        if(phraseStep >= PHRASE_LEN) 0 => phraseStep;
    }

    // ---- SUBSTEP ENVELOPE UPDATES ----
    // Swing: pairs of steps share a fixed total duration (2 * stepDur).
    // Even steps get swingAmt of the pair, odd steps get the rest.
    // swingAmt=0.5 → straight, 0.62 → groovy shuffle
    stepDur => dur thisStepDur;
    if(s % 2 == 0) {
        stepDur * 2.0 * swingAmt => thisStepDur;
    } else {
        stepDur * 2.0 * (1.0 - swingAmt) => thisStepDur;
    }
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        // Kick pitch envelope: deeper, rounder, longer tail
        if(kickOsc.gain() > 0.005) {
            38.0 + 80.0 * Math.exp(-kickPh * 8.0) => kickOsc.freq;
            kickOsc.freq() * 4.0 => kickLPF.freq;
            kickOsc.gain() * 0.95 => kickOsc.gain;
            kickPh + 0.08 => kickPh;
        } else {
            0.0 => kickOsc.gain;
        }

        // Impact decay
        if(impactG.gain() > 0.01) {
            impactG.gain() * 0.97 => impactG.gain;
            impactOsc.freq() * 0.998 => impactOsc.freq;
        } else {
            0.0 => impactG.gain;
            0.0 => impactOsc.gain;
        }

        // Riser filter smooth
        riserBP.freq() + (riserFreqTarget - riserBP.freq()) * 0.05 => riserBP.freq;

        // Bass filter slide + decay
        bassF.freq() + (bassFiltTarget - bassF.freq()) * 0.12 => bassF.freq;
        if(bassFiltTarget > 220.0) bassFiltTarget * 0.994 => bassFiltTarget;

        // Lead filter — gentle movement, sine doesn't need aggressive sweep
        ldF.freq() + (ldFiltTarget - ldF.freq()) * 0.03 => ldF.freq;
        if(ldFiltTarget > 1200.0) ldFiltTarget * 0.999 => ldFiltTarget;

        // Lead amplitude envelope — slower attack/release for sine tone
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.05 => ldAmpCurrent;
        ldAmpCurrent => ldDry.gain;
        if(ldAmpTarget > 0.01) ldAmpTarget * 0.988 => ldAmpTarget;

        // Pad filter sweep with LFO modulation
        0.002 => float padLfoRate;
        if(arrLevel >= 3) padLfoRate * 1.5 => padLfoRate;
        if(phraseBar % 4 == 2) padLfoRate * 1.3 => padLfoRate;
        if(phraseBar >= 12) padLfoRate * 0.7 => padLfoRate;
        padLfoPhase + padLfoRate => padLfoPhase;
        Math.sin(padLfoPhase) * 200.0 => float padLfoMod;
        padF.freq() + ((padFiltTarget + padLfoMod) - padF.freq()) * 0.015 => padF.freq;
        if(padFiltTarget > 300.0) padFiltTarget * 0.9997 => padFiltTarget;
        padG.gain() + (padGainTarget - padG.gain()) * 0.01 => padG.gain;
        if(transition == 4) 0.0 => padGainTarget;

        // FX: smooth HPF back toward 20Hz when not active (skip during intro + HPF sweep)
        if(fxType != 1 && !introActive) fxHPF.freq() + (20.0 - fxHPF.freq()) * 0.04 => fxHPF.freq;

        // Master gain smooth
        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain * volume => master.gain;

        thisStepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
