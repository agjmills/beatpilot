// reggae.ck - Beatpilot Reggae Engine
// Warm, bright reggae with one-drop rhythm, guitar skanks, and uplifting progressions.
// Inspired by Bob Marley, Toots, Jimmy Cliff. Sunshine vibes.
// Reads state from /tmp/beatpilot-state (written by hook.sh).
// Energy (0-3) controls layer density.

// ============ SAMPLE DETECTION ============
me.dir() + "/../samples/reggae/" => string smpDir;
0 => int useSamples;

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
// Dub: simple minor progressions. i-iv, i-v-iv, i-bVII-iv, i-iv-bVII-v
// Dub progressions: minor, moody, each chord different
[[0, 3, 4, 2], [0, 4, 3, 1], [0, 2, 3, 4], [0, 3, 1, 4]] @=> int progs[][];
0 => int progIdx;
0 => int chordIdx;
0 => int chordRoot;
0 => int skankKey; // tracks the current guitar sample's root note
[2, 5, 3, 9] @=> int skankKeys[]; // D minor, F major, Eb, A
0 => int phraseBar;
0 => int phraseRepeat;
int chordSub[4];

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
Gain masterOut => HPF fxHPF => dac;
20.0 => fxHPF.freq; 0.7 => fxHPF.Q;
Gain master => Gain dryOut => masterOut;
0.0 => master.gain;

// ============ MULTI-TAP DELAY REVERB ============
// Dub reverb: darker and splashier than other genres. Higher feedback, lower LP.
master => DelayL rv1 => Gain rvFb1 => LPF rvF1 => Gain rvMix => masterOut;
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

// ============ SAMPLE BUFFERS ============
SndBuf smpKick => Gain smpKickG => master;
SndBuf smpSnare => Gain smpSnareG => master;
SndBuf smpRimshot => Gain smpRimshotG => master;
SndBuf smpHat => Gain smpHatG => master;
SndBuf smpHatOpen => Gain smpHatOpenG => master;
0.0 => smpKickG.gain; 0.0 => smpSnareG.gain; 0.0 => smpRimshotG.gain;
0.0 => smpHatG.gain; 0.0 => smpHatOpenG.gain;

FileIO smpTest;
if(smpTest.open(smpDir + "kick.wav", FileIO.READ)) {
    smpTest.close();
    smpKick.read(smpDir + "kick.wav");
    smpSnare.read(smpDir + "snare.wav");
    smpRimshot.read(smpDir + "rimshot.wav");
    smpHat.read(smpDir + "hat_closed.wav");
    smpHatOpen.read(smpDir + "hat_open.wav");
    smpKick.samples() => smpKick.pos;
    smpSnare.samples() => smpSnare.pos;
    smpRimshot.samples() => smpRimshot.pos;
    smpHat.samples() => smpHat.pos;
    smpHatOpen.samples() => smpHatOpen.pos;
    1 => useSamples;
    <<< "Beatpilot [reggae]: samples loaded" >>>;
} else {
    <<< "Beatpilot [reggae]: no samples found, using synthesis" >>>;
}

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
// Reggae: major, bright, sunshine — pentatonic major, major, mixolydian, major 7
[[0,2,4,7,9], [0,2,4,5,7,9,11], [0,2,4,5,7,9,10], [0,2,4,7,11]] @=> int scales[][];
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
TriOsc bassOsc1 => LPF bassF => Gain bassG => master;
TriOsc bassOsc2 => bassF;
0.4 => bassOsc1.gain; 0.35 => bassOsc2.gain;
400.0 => bassF.freq; 0.8 => bassF.Q; // gentle filter, no resonance
0.12 => bassG.gain;
400.0 => float bassFiltTarget;
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
// Skank: sample-based if available, Mandolin fallback
Mandolin skankSynth => ADSR skankChop => LPF skankFilt => Gain skankG => master;
skankChop.set(0.5::ms, 60::ms, 0.0, 15::ms);
3800.0 => skankFilt.freq; 0.8 => skankFilt.Q;
// Sample skanks — 4 different chords, selected by seed
SndBuf smpSkank[4];
Gain smpSkankG => master;
0.0 => smpSkankG.gain;
0 => int useSkankSamples;

FileIO skTest;
if(skTest.open(smpDir + "skank_dminor.wav", FileIO.READ)) {
    skTest.close();
    smpSkank[0].read(smpDir + "skank_dminor.wav");
    smpSkank[1].read(smpDir + "skank_fmajor.wav");
    smpSkank[2].read(smpDir + "skank_eflat.wav");
    smpSkank[3].read(smpDir + "skank_a.wav");
    for(0 => int i; i < 4; i++) {
        smpSkank[i] => smpSkankG;
        smpSkank[i].samples() => smpSkank[i].pos;
    }
    0.25 => smpSkankG.gain;
    1 => useSkankSamples;
    <<< "Beatpilot [reggae]: guitar skanks loaded" >>>;
}
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
            0 => phraseRepeat;
            for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
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

            // Coming back from silence? Spacey dub intro
            if(masterTarget < 0.01 && newEnergy >= 2) {
                if((seed + newSeed) % 2 == 0) {
                    1 => introActive;
                    0 => introBar;
                    if((seed * 3 + newSeed) % 2 == 0) 2 => introLen;
                    else 4 => introLen;
                    1000.0 => fxHPF.freq;
                }
            }

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
        if(phraseBar >= 16) {
            0 => phraseBar;
            phraseRepeat + 1 => phraseRepeat;
            for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
            if(phraseRepeat % 3 == 2 && energy >= 2) {
                (seed * 13 + phraseRepeat) % 4 => int subIdx;
                // Dub: up a 4th (+3 scale degrees)
                (progs[progIdx][subIdx] + 3) % 5 => chordSub[subIdx];
            }
        }
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        progs[progIdx][chordIdx] => chordRoot;
        if(chordSub[chordIdx] >= 0) chordSub[chordIdx] => chordRoot;

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

        // ---- INTRO: call to the dancefloor ----
        if(introActive) {
            introBar + 1 => introBar;
            if(introBar > introLen) {
                // DROP — one-drop groove lands
                0 => introActive;
                20.0 => fxHPF.freq;
                0.28 => rvMix.gain;
                0.45 => rvFb1.gain; 0.42 => rvFb2.gain;
                0.06 => dlyWetTarget;
                0.55 => dlyFb.gain;
            } else {
                introBar $ float / introLen $ float => float p;
                // HPF sweeps down: reveal the sub bass gradually
                1000.0 * (1.0 - p) * (1.0 - p) + 20.0 => fxHPF.freq;
                // Reverb + delay wash: classic dub intro — echoes building
                0.38 => rvMix.gain;
                0.50 => rvFb1.gain; 0.48 => rvFb2.gain;
                0.10 => dlyWetTarget;
                0.62 => dlyFb.gain;
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
                    // HPF sweep: subtle for dub — don't thin the sub too much
                    20.0 + p * p * 600.0 => fxHPF.freq;
                } else if(fxType == 2) {
                    // Reverb wash: boost dub splash
                    0.28 + p * 0.18 => rvMix.gain;
                    0.45 + p * 0.10 => rvFb1.gain;
                    0.42 + p * 0.10 => rvFb2.gain;
                } else if(fxType == 3) {
                    // Delay throw swell: crank the dub delay wet + feedback
                    0.06 + p * 0.08 => dlyWetTarget;
                    0.55 + p * 0.15 => dlyFb.gain;
                }
            }
        }
        if(fxType == 0 && !introActive) {
            if(rvMix.gain() > 0.29) rvMix.gain() * 0.95 + 0.28 * 0.05 => rvMix.gain;
            if(rvFb1.gain() > 0.46) rvFb1.gain() * 0.95 + 0.45 * 0.05 => rvFb1.gain;
            if(rvFb2.gain() > 0.43) rvFb2.gain() * 0.95 + 0.42 * 0.05 => rvFb2.gain;
            if(dlyFb.gain() > 0.56) dlyFb.gain() * 0.95 + 0.55 * 0.05 => dlyFb.gain;
            if(dlyWetTarget > 0.065) 0.06 => dlyWetTarget;
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

    // ---- KICK (one-drop: beat 3, humanized) ----
    if(!kickMuted && kPat[energy][s]) {
        0.0 => kickPh;
        ((seed * 17 + stepCount) % 100 - 50) / 1000.0 => float velDrift;
        0.5 + 0.5 * (kickVel[s] + velDrift) => float kVel;
        if(useSamples) { 0 => smpKick.pos; kVel * 0.30 => smpKickG.gain; }
        kVel * 0.9 => kickOsc.gain;
        kVel * 0.2 => kickClick.gain;
        if(useSamples) { kickOsc.gain() * 0.3 => kickOsc.gain; kickClick.gain() * 0.3 => kickClick.gain; }
        kickClickEnv.keyOn();
    }

    // ---- HATS (off-beat, shuffled) ----
    if(hatFill) {
        (s $ float) / 16.0 => float fillVel;
        if(useSamples) { 0 => smpHat.pos; 0.06 + 0.08 * fillVel => smpHatG.gain; }
        0.02 + 0.06 * fillVel => chG.gain;
        if(useSamples) chG.gain() * 0.3 => chG.gain;
        chEnv.keyOn();
        if(s % 4 == 0) {
            if(useSamples) { 0 => smpHatOpen.pos; 0.06 => smpHatOpenG.gain; }
            ohEnv.keyOn();
        }
    } else {
        if(chPat[energy][s]) {
            if(useSamples) { 0 => smpHat.pos; 0.06 + 0.08 * hatVel[s] => smpHatG.gain; }
            0.02 + 0.05 * hatVel[s] => chG.gain;
            if(useSamples) chG.gain() * 0.3 => chG.gain;
            chEnv.keyOn();
        }
        if(ohPat[energy][s]) {
            if(useSamples) { 0 => smpHatOpen.pos; 0.05 + 0.06 * hatVel[s] => smpHatOpenG.gain; }
            0.02 + 0.03 * hatVel[s] => ohG.gain;
            if(useSamples) ohG.gain() * 0.3 => ohG.gain;
            ohEnv.keyOn();
        }
    }

    // ---- SNARE / RIMSHOT (one-drop on beat 3, with delay throws) ----
    if(snrPat[energy][s]) {
        snrVel[s] => float sVel;
        if(useSamples) { 0 => smpRimshot.pos; sVel * 0.20 => smpRimshotG.gain; }
        sVel * 0.08 => snrG.gain;
        if(useSamples) snrG.gain() * 0.3 => snrG.gain;
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

    // ---- DRUM MICRO-VARIATION ----
    if(energy >= 2) {
        (seed + phraseBar * 7) % 8 => int drumVar;
        // Extra ghost hat on empty step
        if(drumVar < 3 && s == 9 && !chPat[energy][s]) {
            0.015 => chG.gain;
            chEnv.keyOn();
        }
        // Extra open hat ghost
        if(drumVar >= 6 && s == 5 && !ohPat[energy][s]) {
            0.012 => ohG.gain;
            ohEnv.keyOn();
        }
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
        if(useSkankSamples) {
            // Guitar skank — walk through a chord progression
            // Samples: 0=Dm, 1=F, 2=Eb, 3=A
            // Progression: Dm - Dm - F - Dm (4-bar cycle using phraseBar)
            [0, 0, 1, 0,  0, 0, 1, 0,  0, 1, 0, 1,  0, 0, 1, 0] @=> int skankProg[];
            skankProg[phraseBar] => int skIdx;
            1.0 => smpSkank[skIdx].rate;
            0 => smpSkank[skIdx].pos;
            0.20 + Math.random2f(0.0, 0.08) => smpSkankG.gain;
        } else {
            // Synth fallback
            Std.mtof(note(chordRoot, 4)) => skankSynth.freq;
            0.4 + Math.random2f(0.0, 0.2) => skankSynth.pluckPos;
            0.8 => skankSynth.pluck;
            skankChop.keyOn();
        }
    }

    // ---- BASS (proper reggae groove in D minor) ----
    // D=38, F=41, G=43, A=45, Bb=46, C=48 (octave 2-3 range)
    // Energy 1: simple root on beats
    // Energy 2: classic reggae walking line
    // Energy 3: busier, syncopated
    if(transition != 4 && energy >= 1 && arrLevel >= 1) {
        -1 => int bassMidi;
        if(energy == 1) {
            // Minimal: D on beat 1 and 3
            if(s == 0) 38 => bassMidi;
            else if(s == 8) 38 => bassMidi;
        } else if(energy == 2) {
            // Classic reggae bass: D-F-G-A walkup with bounce
            if(s == 0) 38 => bassMidi;       // D root
            else if(s == 6) 41 => bassMidi;  // F (minor third) — offbeat
            else if(s == 8) 43 => bassMidi;  // G (fourth)
            else if(s == 14) 45 => bassMidi; // A (fifth) — pickup into next bar
        } else {
            // Full groove + occasional solo bars
            (seed + phraseBar * 3) % 8 => int bassVar;
            if(bassVar == 0 && phraseBar % 4 == 2) {
                // Solo bar: fast run up the scale — bar 3 of each chord
                if(s == 0) 38 => bassMidi;       // D
                else if(s == 2) 41 => bassMidi;  // F
                else if(s == 4) 43 => bassMidi;  // G
                else if(s == 6) 45 => bassMidi;  // A
                else if(s == 8) 46 => bassMidi;  // Bb
                else if(s == 10) 48 => bassMidi; // C
                else if(s == 12) 50 => bassMidi; // D octave up
                else if(s == 14) 48 => bassMidi; // C — fall back down
            } else if(bassVar == 1 && phraseBar % 4 == 3) {
                // Solo bar: syncopated octave jumps
                if(s == 0) 38 => bassMidi;       // D low
                else if(s == 3) 50 => bassMidi;  // D high
                else if(s == 6) 45 => bassMidi;  // A
                else if(s == 8) 50 => bassMidi;  // D high
                else if(s == 11) 43 => bassMidi; // G
                else if(s == 14) 36 => bassMidi; // C — chromatic walk
            } else if(bassVar == 2 && phraseBar % 8 == 7) {
                // Solo bar: descending triplet feel
                if(s == 0) 50 => bassMidi;       // D high
                else if(s == 2) 48 => bassMidi;  // C
                else if(s == 4) 46 => bassMidi;  // Bb
                else if(s == 7) 45 => bassMidi;  // A
                else if(s == 9) 43 => bassMidi;  // G
                else if(s == 12) 41 => bassMidi; // F
                else if(s == 14) 38 => bassMidi; // D — home
            } else {
                // Normal energy 3 groove
                if(s == 0) 38 => bassMidi;       // D root
                else if(s == 3) 41 => bassMidi;  // F ghost
                else if(s == 6) 43 => bassMidi;  // G offbeat
                else if(s == 8) 45 => bassMidi;  // A
                else if(s == 10) 43 => bassMidi; // G passing
                else if(s == 14) 36 => bassMidi; // C — chromatic walk up
            }
        }

        if(bassMidi >= 0) {
            Std.mtof(bassMidi) => float bFreq;
            bFreq => bassOsc1.freq;
            bFreq * 1.002 => bassOsc2.freq;
            bassDriftPhase + 0.0001 => bassDriftPhase;
            bassOsc2.freq() + Math.sin(bassDriftPhase) * 0.3 => bassOsc2.freq;
            if(s % 4 != 0) {
                450.0 => bassFiltTarget; // offbeat pop
            } else {
                250.0 => bassFiltTarget; // downbeat round
            }
            0.12 => bassG.gain;
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
        // Motif variation per repetition
        phraseBar / 4 => int motifRep;
        if(motifRep == 1 && (seed + phraseStep) % 5 == 0) -1 => deg;
        if(motifRep == 3 && deg >= 0 && phraseStep % 8 == 6) deg - 1 => deg;
        if(deg >= 0) {
            scales[scaleType] @=> int scl[];
            (deg + chordRoot) % scl.cap() => deg;
            if(deg < 0) deg + scl.cap() => deg;
            4 => int ldOct;
            if(energy >= 3 && phraseStep >= 32) 5 => ldOct;
            if(motifRep == 2 && phraseStep >= 32 && phraseStep < 48) 5 => ldOct;
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
            0.03 => float ldVel;
            if(localStep % 4 == 0) 0.05 => ldVel;
            else if(localStep % 2 == 0) 0.04 => ldVel;
            if(phraseStep >= 32 && phraseStep < 48) ldVel * 1.15 => ldVel;
            if(phraseStep >= 48) ldVel * 0.6 => ldVel;
            1000.0 + Math.random2f(0.0, 400.0) => ldFiltTarget; // darker, sits behind the guitar
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
        if(bassFiltTarget > 120.0) bassFiltTarget * 0.994 => bassFiltTarget;

        // Lead filter — gentle movement, organ-like
        ldF.freq() + (ldFiltTarget - ldF.freq()) * 0.025 => ldF.freq;
        if(ldFiltTarget > 800.0) ldFiltTarget * 0.999 => ldFiltTarget;

        // Lead amplitude envelope — moderate attack/release
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.04 => ldAmpCurrent;
        ldAmpCurrent => ldDry.gain;
        if(ldAmpTarget > 0.01) ldAmpTarget * 0.99 => ldAmpTarget;

        // Pad filter sweep with LFO — slow, dark, breathing
        0.0015 => float padLfoRate;
        if(arrLevel >= 3) padLfoRate * 1.4 => padLfoRate;
        if(phraseBar % 4 == 2) padLfoRate * 1.3 => padLfoRate;
        if(phraseBar >= 12) padLfoRate * 0.7 => padLfoRate;
        padLfoPhase + padLfoRate => padLfoPhase;
        Math.sin(padLfoPhase) * 120.0 => float padLfoMod;
        padF.freq() + ((padFiltTarget + padLfoMod) - padF.freq()) * 0.012 => padF.freq;
        if(padFiltTarget > 250.0) padFiltTarget * 0.9998 => padFiltTarget;
        padG.gain() + (padGainTarget - padG.gain()) * 0.008 => padG.gain;
        if(transition == 4) 0.0 => padGainTarget;

        // Delay wet level smooth — important for dub dynamics
        dlyWet.gain() + (dlyWetTarget - dlyWet.gain()) * 0.02 => dlyWet.gain;

        // Snare delay send decay — don't leave it open
        if(snrToDelay.gain() > 0.01) snrToDelay.gain() * 0.98 => snrToDelay.gain;

        // FX: smooth HPF back toward 20Hz when not active (skip during intro + HPF sweep)
        if(fxType != 1 && !introActive) fxHPF.freq() + (20.0 - fxHPF.freq()) * 0.04 => fxHPF.freq;

        // Master gain smooth
        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain * volume => master.gain;

        thisStepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
