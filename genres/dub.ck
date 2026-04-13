// dub.ck - Beatpilot Dub Engine
// Deep, spacious dub with one-drop rhythm, massive delay throws, and heavy sub bass.
// Inspired by Lee "Scratch" Perry, King Tubby. The FX ARE the instrument.
// Reads state from /tmp/beatpilot-state (written by hook.sh).
// Energy (0-3) controls layer density and delay throw intensity.

// ============ CLOCK ============
75.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;
4 => int SUBSTEPS;
0.58 => float swingAmt; // subtle shuffle, similar to DnB

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

// ============ PHRASE / SONG STRUCTURE ============
// Chord progression: 4 chords, each lasts 4 bars = 16-bar phrase
// Dub: simple minor progressions. i-iv, i-v-iv, i-bVII-iv, i-iv-bVII-v
[[0, 3, 0, 3], [0, 4, 3, 0], [0, 6, 3, 0], [0, 3, 6, 4]] @=> int progs[][];
0 => int progIdx;
0 => int chordIdx;
0 => int chordRoot;
0 => int phraseBar;

// Lead motif: 4-bar phrase (64 steps) — very sparse for dub, let delay fill space
64 => int PHRASE_LEN;
int motif[64];
int bassLine[64];
int delayThrow[64]; // 1 = send this note to the delay throw bus
0 => int motifGenerated;
0 => int phraseStep;

// Arrangement mask: which bars have which layers active
// 0=minimal, 1=bass only, 2=bass+pad/skank, 3=bass+pad+lead
int arrangement[16];

fun void generateMotif() {
    seed => int s;
    for(0 => int i; i < PHRASE_LEN; i++) {
        -1 => motif[i];
        -1 => bassLine[i];
        0 => delayThrow[i];
    }

    // --- CELL-BASED COMPOSITION ---
    // Dub: very sparse — 2 notes per bar max, delay does the rest
    int cellDeg[3];
    int cellPos[3];

    0 => cellDeg[0];
    [1, 2, -1, 2, 1, -2] @=> int leaps[];
    leaps[s % leaps.cap()] => int leap1;
    leap1 => cellDeg[1];
    [-1, 0, 1, -1, 0] @=> int resolves[];
    cellDeg[1] + resolves[(s / 2) % resolves.cap()] => cellDeg[2];

    // Dub cell rhythm: wide spacing, spacious — let delay echo fill gaps
    [[0, 6, 12], [0, 8, 14], [0, 6, 10], [2, 8, 14], [0, 10, 14]] @=> int cellRhythms[][];
    cellRhythms[(s / 3) % cellRhythms.cap()] @=> int cR[];
    cR[0] => cellPos[0]; cR[1] => cellPos[1]; cR[2] => cellPos[2];

    s % 3 => int varType;

    // Bar 1: cell — only 2 notes (skip last for maximum space)
    cellDeg[0] => motif[cellPos[0]];
    cellDeg[1] => motif[cellPos[1]];
    // Throw the second note into delay
    1 => delayThrow[cellPos[1]];

    // Bar 2: cell varied — still sparse
    if(varType == 0) {
        cellDeg[0] + 2 => motif[16 + cellPos[0]];
        cellDeg[1] + 2 => motif[16 + cellPos[1]];
        1 => delayThrow[16 + cellPos[0]]; // throw first note this time
    } else if(varType == 1) {
        cellDeg[0] => motif[16 + cellPos[0]];
        cellDeg[0] - leap1 => motif[16 + cellPos[2]];
        1 => delayThrow[16 + cellPos[2]];
    } else {
        cellDeg[2] + 1 => motif[16 + cellPos[0]];
        cellDeg[1] => motif[16 + cellPos[1]];
        1 => delayThrow[16 + cellPos[1]];
    }

    // Bar 3: development — 3 notes, the busiest it gets
    cellDeg[0] + 3 => motif[32 + cellPos[0]];
    1 => delayThrow[32 + cellPos[0]];
    cellDeg[0] - 1 => motif[32 + 8]; // approach note
    cellDeg[1] => motif[32 + cellPos[2]];
    1 => delayThrow[32 + cellPos[2]];

    // Bar 4: half cell + resolve — very sparse
    cellDeg[0] + 1 => motif[48];
    0 => motif[56]; // resolve to root
    1 => delayThrow[48]; // throw, let echo carry into next phrase

    // --- BASS LINE: cell-derived, heavy sub ---
    // Dub bass: long sustained notes on strong beats, very simple
    // Bar 1: root on beat 1, hold; cell interval on beat 3
    0 => bassLine[0];
    cellDeg[1] => bassLine[8];

    // Bar 2: follows variation
    if(varType == 0) {
        2 => bassLine[16]; cellDeg[1] + 2 => bassLine[24];
    } else if(varType == 1) {
        0 => bassLine[16]; 0 - leap1 => bassLine[24];
    } else {
        1 => bassLine[16]; cellDeg[2] + 1 => bassLine[24];
    }

    // Bar 3: slightly busier
    0 => bassLine[32]; cellDeg[1] => bassLine[36];
    3 => bassLine[40]; 0 => bassLine[44];

    // Bar 4: simple roots
    0 => bassLine[48];
    0 => bassLine[56];

    // --- ARRANGEMENT: dub-specific templates ---
    // Dub loves stripping down to just bass + delay echoes
    s % 4 => int arrType;
    if(arrType == 0) {
        // Build: bass → +pad/skank → +lead → strip to bass + echoes
        [1,1,1,1, 2,2,2,2, 3,3,3,3, 1,1,2,2] @=> int arrA[];
        for(0 => int i; i < 16; i++) arrA[i] => arrangement[i];
    } else if(arrType == 1) {
        // Call-response: lead thrown into delay, then just echoes
        [1,1,3,3, 1,1,3,3, 2,2,3,3, 3,3,1,1] @=> int arrB[];
        for(0 => int i; i < 16; i++) arrB[i] => arrangement[i];
    } else if(arrType == 2) {
        // Full then strip: classic dub breakdown
        [2,2,3,3, 3,3,3,3, 1,1,1,1, 2,2,3,3] @=> int arrC[];
        for(0 => int i; i < 16; i++) arrC[i] => arrangement[i];
    } else {
        // Spacious: mostly sparse, occasional full bars
        [1,1,2,2, 1,1,3,3, 2,2,1,1, 3,3,2,1] @=> int arrD[];
        for(0 => int i; i < 16; i++) arrD[i] => arrangement[i];
    }

    0 => phraseStep;
    1 => motifGenerated;
}

// ============ TRANSITION STATE ============
0 => int transition;
0 => int transitionBars;
0 => int transitionStep;
0 => int lastTransitionTs;

// ============ AUTO-EVOLUTION ============
// Dub auto-evolution: normal → strip to bass+delay → drums return with throws → full → breakdown with reverb tails
0 => int autoSection;
0 => int autoSectionBar;
0 => int autoActive;
[0, 8, 8, 6, 1] @=> int autoSectionLen[];
[1, 2, 3, 4, 0] @=> int autoNextSection[];

// ============ MASTER BUS ============
Gain master => Gain dryOut => dac;
0.0 => master.gain;

// ============ MULTI-TAP DELAY REVERB ============
// Dub reverb: darker and splashier than other genres. Higher feedback, lower LP.
master => DelayL rv1 => Gain rvFb1 => LPF rvF1 => Gain rvMix => dac;
master => DelayL rv2 => Gain rvFb2 => LPF rvF2 => rvMix;
master => DelayL rv3 => Gain rvFb3 => LPF rvF3 => rvMix;
master => DelayL rv4 => Gain rvFb4 => LPF rvF4 => rvMix;
// Cross-feed for density
rvFb1 => rv3; rvFb2 => rv4; rvFb3 => rv1; rvFb4 => rv2;
// Longer delay times for dub splash
0.2::second => rv1.max; 0.1573::second => rv1.delay;
0.3::second => rv2.max; 0.2531::second => rv2.delay;
0.4::second => rv3.max; 0.3347::second => rv3.delay;
0.5::second => rv4.max; 0.4219::second => rv4.delay;
// Dark, splashy — lower LP, higher feedback than other genres
1200.0 => rvF1.freq; 1000.0 => rvF2.freq;
900.0 => rvF3.freq; 800.0 => rvF4.freq;
0.45 => rvFb1.gain; 0.42 => rvFb2.gain;
0.38 => rvFb3.gain; 0.35 => rvFb4.gain;
0.28 => rvMix.gain;
0.72 => dryOut.gain;

// ============ DUB DELAY THROW BUS ============
// THE signature dub sound — long feedback delay with filtering
// Certain notes and snare hits get "thrown" into this delay
Gain delaySend => DelayL dubDly => LPF dlyLP => HPF dlyHP => Gain dlyFb => delaySend;
dlyFb => Gain dlyWet => master;

// Dotted quarter = stepDur * 6 at 75 BPM
(stepDur * 6) => dubDly.max => dubDly.delay;
0.55 => dlyFb.gain;     // high feedback — many repeats, slowly dying
1500.0 => dlyLP.freq;   // echoes get darker with each repeat
300.0 => dlyHP.freq;    // echoes get thinner — removes mud
0.06 => dlyWet.gain;    // wet level to master
0.0 => float dlyWetTarget;
0.06 => dlyWetTarget;

// ============ SCALES ============
// Dub: minor pentatonic, natural minor, dorian — almost always minor
[[0,3,5,7,10], [0,2,3,5,7], [0,2,3,5,7,9,10], [0,2,3,5,7,8,10]] @=> int scales[][];
// 0: minor pentatonic, 1: minor pent alt voicing, 2: dorian, 3: natural minor

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    if(degree < 0) return 0;
    return key + octave * 12 + scl[degree % scl.cap()] + (degree / scl.cap()) * 12;
}

// ============ KICK ============
// Dub kick: very deep, round, long sustain — ONE DROP on beat 3
SinOsc kickOsc => LPF kickLPF => Gain kickG => master;
0.0 => kickOsc.gain;
250.0 => kickLPF.freq;
0.4 => kickG.gain;
0.0 => float kickPh;

// Click transient — softer than techno, more thud than click
Noise kickClick => BPF kickClickBP => ADSR kickClickEnv => kickG;
2500.0 => kickClickBP.freq; 1.2 => kickClickBP.Q;
kickClickEnv.set(0.3::ms, 12::ms, 0.0, 5::ms);
0.2 => kickClick.gain;

// One-drop patterns: kick on beat 3 (step 8), NOT beat 1!
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0]] @=> int kPat[][];

// ============ VELOCITY MAPS ============
// Kick: beat 3 is the one-drop — HARD. Everything else ghost-level.
[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.85, 0.0, 0.0, 0.0] @=> float kickVel[];
// Hat: off-beat accents, ghost on downbeats — dub hats are felt not heard
[0.3, 0.2, 0.8, 0.3, 0.3, 0.2, 0.9, 0.3, 0.3, 0.2, 0.8, 0.3, 0.3, 0.2, 0.9, 0.4] @=> float hatVel[];
// Snare: one-drop accent on beat 3
[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0] @=> float snrVel[];

// ============ CLOSED HAT ============
// Dub hats: off-beat, shuffled — "tss tss tss tss"
Noise chN => HPF chHP => ADSR chEnv => Gain chG => master;
7000.0 => chHP.freq;
chEnv.set(0.3::ms, 30::ms, 0.0, 8::ms);
0.06 => chG.gain;

// Off-beat hat patterns — steps 2, 6, 10, 14 (off-beats)
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [0,0,1,0,0,1,1,0,0,0,1,0,0,1,1,0]] @=> int chPat[][];

// ============ OPEN HAT ============
Noise ohN => BPF ohBP => ADSR ohEnv => Gain ohG => master;
8000.0 => ohBP.freq; 1.2 => ohBP.Q;
ohEnv.set(1::ms, 180::ms, 0.02, 120::ms);
0.04 => ohG.gain;

// Open hat: sparse, usually on off-beats
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
 [0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0]] @=> int ohPat[][];

// ============ SNARE / RIMSHOT ============
// Dub snare: rimshot-like, layered with kick on beat 3 (one-drop)
// Also gets thrown into delay for that classic dub snare echo
Noise snrN => BPF snrBP => ADSR snrEnv => Gain snrG => master;
1800.0 => snrBP.freq; 2.5 => snrBP.Q;
snrEnv.set(0.3::ms, 45::ms, 0.0, 15::ms);
0.0 => snrG.gain;
// Snare also feeds the delay throw bus
snrG => Gain snrToDelay => delaySend;
0.0 => snrToDelay.gain;

// Snare on beat 3 — layered with kick for the one-drop
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0]] @=> int snrPat[][];

// ============ SUB BASS ============
// Dub sub bass: THE foundation. Deep sine, heaviest bass in any genre.
// Detuned pair for width + slow drift LFO
SinOsc bassOsc1 => LPF bassF => Gain bassG => master;
SinOsc bassOsc2 => bassF;
0.7 => bassOsc1.gain; 0.65 => bassOsc2.gain;
120.0 => bassF.freq; 3.0 => bassF.Q;
0.18 => bassG.gain;
120.0 => float bassFiltTarget;
0.0 => float bassDriftPhase;
// Bass also feeds reverb lightly
// bass routes through master to reverb
// reverb send via master bus

// ============ MELODICA / ORGAN LEAD ============
// SinOsc + TriOsc layered for a reedy, organ-like tone — NOT Rhodes, NOT FM
// Breathy, simple. Gets thrown into delay.
SinOsc ldSin1 => LPF ldF => Gain ldDry => master;
SinOsc ldSin2 => ldF; // detuned pair
TriOsc ldTri1 => ldF;
TriOsc ldTri2 => ldF; // detuned pair
0.4 => ldSin1.gain; 0.35 => ldSin2.gain;
0.25 => ldTri1.gain; 0.2 => ldTri2.gain;
2200.0 => ldF.freq; 1.2 => ldF.Q;
0.0 => ldDry.gain;
2200.0 => float ldFiltTarget;
0.0 => float ldAmpTarget;
0.0 => float ldAmpCurrent;
-1 => int lastLeadDeg;
0.0 => float ldDriftPhase;

// Lead feeds the delay throw bus (selectively — via delayThrow array)
ldDry => Gain ldToDelay => delaySend;
0.0 => ldToDelay.gain;

// Lead also feeds reverb
// lead routes through master to reverb
// reverb send via master bus

// ============ PAD ============
// Dark, minor pad — detuned TriOsc pairs through dark filter
TriOsc padOsc1 => LPF padF => Gain padG => master;
SinOsc padOsc2 => padF;
TriOsc padOsc3 => padF;
0.25 => padOsc1.gain; 0.3 => padOsc2.gain; 0.2 => padOsc3.gain;
350.0 => padF.freq; 1.5 => padF.Q;
0.0 => padG.gain;
0.0 => float padGainTarget;
350.0 => float padFiltTarget;
0 => int padLastDeg;
0.0 => float padLfoPhase;

// Pad feeds reverb heavily — dub reverb tails are essential
// pad routes through master to reverb
// reverb send via master bus

// ============ SKANK GUITAR ============
// Short, choppy chord hits on off-beats — the "chick-a chick-a" rhythm
// Filtered noise + TriOsc for percussive, muted guitar approximation
// Skank: StifKarp — muted pluck, short and choppy
StifKarp skank => ADSR skankChop => LPF skankFilt => Gain skankG => master;
// Chop envelope: cuts the sustain dead — muted guitar feel
skankChop.set(0.5::ms, 40::ms, 0.0, 10::ms);
1200.0 => skankFilt.freq; 0.8 => skankFilt.Q; // dark, muted
0.0 => skankG.gain;

// Skank feeds reverb for dub wash
// skank routes through master to reverb
// reverb send via master bus

// Skank pattern: off-beats — steps 2, 6, 10, 14
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0]] @=> int skankPat[][];

// ============ RISER / FX ============
Noise riserN => BPF riserBP => Gain riserG => master;
500.0 => riserBP.freq; 4.0 => riserBP.Q;
0.0 => riserG.gain;
500.0 => float riserFreqTarget;

// Impact: low sine boom for drop moments
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
            newScale % scales.cap() => scaleType;
            newSeed % 256 => seed;
            newSeed % 2 => variant;
            seed % progs.cap() => progIdx;
            0 => phraseBar;
            0 => chordIdx;
            progs[progIdx][0] => chordRoot;
            generateMotif();

            // --- TRANSITION TRIGGERS ---
            if(transition == 0 && energy >= 1) {
                if(newEnergy >= 3 && energy < 3) {
                    // Big moment: riser into heavy drop
                    2 => transition;
                    3 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy >= 2 && newEnergy > energy) {
                    // Medium: short build
                    2 => transition;
                    2 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy == 0) {
                    // Breakdown: strip everything, let delay tails ring
                    4 => transition;
                    2 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy < energy && energy >= 2) {
                    // Wind down: filter sweep
                    4 => transition;
                    1 => transitionBars;
                    0 => transitionStep;
                }
            }

            newEnergy => energy;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;
            1.0 => masterTarget;

            // Cancel auto-evolution on real event
            if(autoActive) {
                0 => autoActive;
                0 => autoSection;
                0 => autoSectionBar;
            }

            if(energy >= 2) {
                0.07 => ldDry.gain;
                0.07 => snrG.gain;
                0.15 => skankG.gain;
            } else {
                0.0 => ldAmpTarget;
                0.0 => snrG.gain;
                0.0 => skankG.gain;
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
                if(transition == 2) {
                    3 => transition; // impact bar
                    1 => transitionBars;
                } else {
                    0 => transition;
                    0.0 => riserG.gain;
                }
            }
        }

        // Advance phrase / chord progression
        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) 0 => phraseBar;
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        progs[progIdx][chordIdx] => chordRoot;

        // Energy decay
        if(barsSinceEvent > 6 && energy > 0 && transition == 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) {
                0.0 => ldAmpTarget;
                0.0 => snrG.gain;
                0.0 => skankG.gain;
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
    }

    // ---- TRANSITION FX ----
    transitionStep + 1 => transitionStep;

    0 => int kickMuted;
    0 => int hatFill;

    if(transition == 2) {
        // DROP: kill kick, riser sweeps up
        1 => kickMuted;
        0.06 + transitionStep * 0.0004 => float rGain;
        if(rGain > 0.1) 0.1 => rGain;
        rGain => riserG.gain;
        500.0 + transitionStep * 60.0 => riserFreqTarget;
        if(riserFreqTarget > 10000.0) 10000.0 => riserFreqTarget;
        if(transitionBars <= 1 && s >= 8) 1 => hatFill;
    } else if(transition == 3) {
        // IMPACT: kick + snare slam back, delay throw on impact
        0 => transition;
        0.0 => riserG.gain;
        0.5 => impactG.gain;
        45.0 => impactOsc.freq;
        0.9 => impactOsc.gain;
        // Big delay throw on the impact
        0.6 => snrToDelay.gain;
        if(s == 0) {
            0.0 => kickPh;
            1.0 => kickOsc.gain;
            kickClickEnv.keyOn();
        }
    } else if(transition == 4) {
        // BREAKDOWN: let delay tails ring, filter everything down
        1 => kickMuted;
        80.0 => bassFiltTarget;
        800.0 => ldFiltTarget;
        0.0 => ldAmpTarget;
        // Boost delay wet so tails become prominent
        0.1 => dlyWetTarget;
    }

    // ---- KICK (one-drop: beat 3) ----
    if(!kickMuted && kPat[energy][s]) {
        0.0 => kickPh;
        0.5 + 0.5 * kickVel[s] => float kVel;
        kVel * 0.9 => kickOsc.gain;
        kVel * 0.2 => kickClick.gain;
        kickClickEnv.keyOn();
    }

    // ---- HATS (off-beat, shuffled) ----
    if(hatFill) {
        (s $ float) / 16.0 => float fillVel;
        0.02 + 0.06 * fillVel => chG.gain;
        chEnv.keyOn();
        if(s % 4 == 0) ohEnv.keyOn();
    } else {
        if(chPat[energy][s]) {
            0.02 + 0.05 * hatVel[s] => chG.gain;
            chEnv.keyOn();
        }
        if(ohPat[energy][s]) {
            0.02 + 0.03 * hatVel[s] => ohG.gain;
            ohEnv.keyOn();
        }
    }

    // ---- SNARE / RIMSHOT (one-drop on beat 3, with delay throws) ----
    if(snrPat[energy][s]) {
        snrVel[s] => float sVel;
        sVel * 0.08 => snrG.gain;
        snrEnv.keyOn();
        // Throw snare into delay — seed-based, not every hit
        if((seed + stepCount) % 3 == 0) {
            0.4 => snrToDelay.gain;
        } else {
            0.0 => snrToDelay.gain;
        }
        // Snare feeds reverb
        // snare echo handled by dub delay throw
    }

    // ---- DRUM FILL (rimshot rolls into delay at phrase boundaries) ----
    if(drumFill > 0 && energy >= 1) {
        if(drumFill == 2) {
            // Big fill (end of 16-bar phrase): snare roll into delay — echoes become the fill
            if(s >= 6 && s % 2 == 0 && !snrPat[energy][s]) {
                0.03 + (s $ float) / 16.0 * 0.05 => snrG.gain;
                snrEnv.keyOn();
                // Throw every fill hit into delay for cascading echoes
                0.5 => snrToDelay.gain;
            }
            // Open hat accents on 10, 14
            if(s == 10 || s == 14) {
                0.04 => ohG.gain;
                ohEnv.keyOn();
            }
        } else {
            // Small fill (end of 4-bar chord): rimshot tap on step 12, thrown into delay
            if(s == 12 && !snrPat[energy][s]) {
                0.04 => snrG.gain;
                snrEnv.keyOn();
                0.4 => snrToDelay.gain;
            }
        }
    }

    // ---- ARRANGEMENT: determine what plays this bar ----
    0 => int arrLevel;
    if(motifGenerated) arrangement[phraseBar] => arrLevel;
    if(energy < 2) { if(arrLevel > 1) 1 => arrLevel; }

    // ---- SKANK GUITAR (off-beat chops, follows arrangement) ----
    if(transition != 4 && energy >= 2 && skankPat[energy][s]) {
        // Pluck then immediately chop — muted reggae hit
        Std.mtof(note(chordRoot, 3)) => skank.freq;
        0.3 + Math.random2f(0.0, 0.15) => skank.pickupPosition;
        0.7 => skank.pluck;
        skankChop.keyOn();
    }

    // ---- SUB BASS (cell-derived, follows arrangement) ----
    if(transition != 4 && energy >= 1 && arrLevel >= 1 && motifGenerated) {
        bassLine[phraseStep % PHRASE_LEN] => int bDeg;
        if(bDeg >= 0) {
            scales[scaleType] @=> int scl[];
            (bDeg + chordRoot) % scl.cap() => bDeg;
            if(bDeg < 0) bDeg + scl.cap() => bDeg;
            1 => int bassOct; // very low — dub sub lives in octave 1-2
            // Occasional octave up on passing tones in bar 3
            if(phraseStep >= 32 && phraseStep < 48 && phraseStep % 4 != 0) 2 => bassOct;
            Std.mtof(note(bDeg, bassOct)) => float bFreq;
            bFreq => bassOsc1.freq;
            bFreq * 1.002 => bassOsc2.freq; // slight detune for width
            // Bass drift LFO — slow, alive
            bassDriftPhase + 0.0001 => bassDriftPhase;
            bassOsc2.freq() + Math.sin(bassDriftPhase) * 0.3 => bassOsc2.freq;
            // Filter follows phrase: opens in bar 3
            if(phraseStep >= 32 && phraseStep < 48) {
                200.0 + Math.random2f(0.0, 100.0) => bassFiltTarget;
            } else {
                120.0 + Math.random2f(0.0, 60.0) => bassFiltTarget;
            }
        }
    }

    // ---- PAD (dark minor, follows arrangement + phrase dynamics) ----
    if(transition != 4 && s == 0 && arrLevel >= 2) {
        chordRoot => int pRoot;
        chordRoot + 2 => int pDeg2;
        chordRoot + 4 => int pDeg3;
        Std.mtof(note(pRoot, 3)) => padOsc1.freq; // lower octave for dub
        Std.mtof(note(pDeg2, 3)) => padOsc2.freq;
        Std.mtof(note(pDeg3, 3)) => padOsc3.freq;
        // Detune for width
        padOsc1.freq() * 0.998 => padOsc1.freq;
        padOsc3.freq() * 1.002 => padOsc3.freq;
        // Pad dynamics follow phrase position
        phraseBar % 4 => int barInChord;
        if(barInChord < 2) 0.035 => padGainTarget;
        else if(barInChord == 2) 0.07 => padGainTarget;
        else 0.025 => padGainTarget;
        if(energy >= 3) padGainTarget * 1.3 => padGainTarget;
        // Dark filter — opens slowly through phrase
        350.0 + barInChord * 80.0 => padFiltTarget;
    } else if(arrLevel < 2) {
        0.0 => padGainTarget;
    }

    // ---- MELODICA/ORGAN LEAD (cell motif, with delay throws) ----
    if(transition != 4 && motifGenerated && arrLevel >= 3) {
        motif[phraseStep % PHRASE_LEN] => int deg;
        if(deg >= 0) {
            scales[scaleType] @=> int scl[];
            (deg + chordRoot) % scl.cap() => deg;
            if(deg < 0) deg + scl.cap() => deg;
            4 => int ldOct;
            if(energy >= 3 && phraseStep >= 32) 5 => ldOct;
            Std.mtof(note(deg, ldOct)) => float ldFreq;
            ldFreq => ldSin1.freq;
            ldFreq * 1.003 => ldSin2.freq; // detune pair
            ldFreq => ldTri1.freq;
            ldFreq * 0.997 => ldTri2.freq; // detune pair
            // Slow pitch drift LFO
            ldDriftPhase + 0.0001 => ldDriftPhase;
            ldSin2.freq() + Math.sin(ldDriftPhase) * 0.5 => ldSin2.freq;

            // Velocity: sparse, bar 3 peaks, bar 4 pulls back
            phraseStep % 16 => int localStep;
            0.04 => float ldVel;
            if(localStep % 4 == 0) 0.07 => ldVel;
            else if(localStep % 2 == 0) 0.05 => ldVel;
            if(phraseStep >= 32 && phraseStep < 48) ldVel * 1.2 => ldVel;
            if(phraseStep >= 48) ldVel * 0.7 => ldVel;
            1400.0 + Math.random2f(0.0, 600.0) => ldFiltTarget;
            ldVel => ldAmpTarget;

            // DELAY THROW: send select notes to the dub delay
            if(delayThrow[phraseStep % PHRASE_LEN]) {
                0.5 => ldToDelay.gain; // hot send to delay bus
            } else {
                0.0 => ldToDelay.gain; // no delay throw
            }
        }
    } else if(arrLevel < 3) {
        0.0 => ldAmpTarget;
        0.0 => ldToDelay.gain;
    }

    // Advance phrase step
    if(motifGenerated) {
        phraseStep + 1 => phraseStep;
        if(phraseStep >= PHRASE_LEN) 0 => phraseStep;
    }

    // ---- SUBSTEP ENVELOPE UPDATES ----
    stepDur => dur thisStepDur;
    if(s % 2 == 0) {
        stepDur * 2.0 * swingAmt => thisStepDur;
    } else {
        stepDur * 2.0 * (1.0 - swingAmt) => thisStepDur;
    }
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        // Kick pitch envelope: deeper and rounder for dub — longer sustain
        if(kickOsc.gain() > 0.005) {
            35.0 + 60.0 * Math.exp(-kickPh * 6.0) => kickOsc.freq;
            kickOsc.freq() * 3.0 => kickLPF.freq;
            kickOsc.gain() * 0.96 => kickOsc.gain; // slower decay = heavier
            kickPh + 0.06 => kickPh;
        } else {
            0.0 => kickOsc.gain;
        }

        // Impact decay
        if(impactG.gain() > 0.01) {
            impactG.gain() * 0.97 => impactG.gain;
            impactOsc.freq() * 0.997 => impactOsc.freq;
        } else {
            0.0 => impactG.gain;
            0.0 => impactOsc.gain;
        }

        // Riser filter smooth
        riserBP.freq() + (riserFreqTarget - riserBP.freq()) * 0.04 => riserBP.freq;

        // Bass filter slide — slow, heavy for dub
        bassF.freq() + (bassFiltTarget - bassF.freq()) * 0.08 => bassF.freq;
        if(bassFiltTarget > 100.0) bassFiltTarget * 0.996 => bassFiltTarget;

        // Lead filter — gentle movement, organ-like
        ldF.freq() + (ldFiltTarget - ldF.freq()) * 0.025 => ldF.freq;
        if(ldFiltTarget > 800.0) ldFiltTarget * 0.999 => ldFiltTarget;

        // Lead amplitude envelope — moderate attack/release
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.04 => ldAmpCurrent;
        ldAmpCurrent => ldDry.gain;
        if(ldAmpTarget > 0.01) ldAmpTarget * 0.99 => ldAmpTarget;

        // Pad filter sweep with LFO — slow, dark, breathing
        padLfoPhase + 0.0015 => padLfoPhase;
        Math.sin(padLfoPhase) * 120.0 => float padLfoMod;
        padF.freq() + ((padFiltTarget + padLfoMod) - padF.freq()) * 0.012 => padF.freq;
        if(padFiltTarget > 250.0) padFiltTarget * 0.9998 => padFiltTarget;
        padG.gain() + (padGainTarget - padG.gain()) * 0.008 => padG.gain;
        if(transition == 4) 0.0 => padGainTarget;

        // Delay wet level smooth — important for dub dynamics
        dlyWet.gain() + (dlyWetTarget - dlyWet.gain()) * 0.02 => dlyWet.gain;

        // Snare delay send decay — don't leave it open
        if(snrToDelay.gain() > 0.01) snrToDelay.gain() * 0.98 => snrToDelay.gain;

        // Master gain smooth
        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain * volume => master.gain;

        thisStepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
