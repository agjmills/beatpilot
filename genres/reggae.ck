// reggae.ck - Beatpilot Reggae Engine
// Warm, bright reggae with one-drop rhythm, guitar skanks, and uplifting progressions.
// Inspired by Bob Marley, Toots, Jimmy Cliff. Sunshine vibes.
// Reads state from <run dir>/state (see lib/paths.sh), written by the adapters or the mod.
// Energy (0-3) controls layer density.

// ---- Runtime paths: `chuck genre.ck:<run dir>`; legacy /tmp without one ----
string statePath; string volumePath; string nowPath;
if(me.args() > 0) {
    me.arg(0) + "/state" => statePath;
    me.arg(0) + "/volume" => volumePath;
    me.arg(0) + "/now" => nowPath;
} else {
    "/tmp/beatpilot-state" => statePath;
    "/tmp/beatpilot-volume" => volumePath;
    "" => nowPath;
}
-1 => int musicSig; // key/scale/seed currently applied (-1 = none yet)


// ============ SAMPLE DETECTION ============
me.dir() + "/../samples/reggae/" => string smpDir;
0 => int useSamples;

// ============ CLOCK ============
75.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;
4 => int SUBSTEPS;
0.60 => float swingAmt; // one-drop shuffle: lazier than DnB, straighter than lofi

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
// Chord progression: 4 chords, each lasts 4 bars = 16-bar phrase.
// Progressions are per mode (scale degrees, 0-based) so every chord is a real
// major/minor triad in that mode — no diminished chords, no pentatonic "chords".
// progs[][] holds the set for the current scale (copied in on each new tune).
[[[0, 3, 4, 3], [0, 5, 3, 4], [0, 4, 5, 3], [0, 3, 1, 4]],   // major:  I-IV-V-IV, I-vi-IV-V, I-V-vi-IV, I-IV-ii-V
 [[0, 6, 3, 0], [0, 3, 0, 6], [0, 6, 3, 4], [0, 1, 3, 6]],   // mixolydian: I-bVII-IV-I, I-IV-I-bVII, I-bVII-IV-v, I-ii-IV-bVII
 [[0, 3, 0, 3], [0, 6, 3, 0], [0, 3, 6, 4], [0, 2, 3, 4]],   // dorian: i-IV vamp, i-bVII-IV-i, i-IV-bVII-v, i-bIII-IV-v
 [[0, 3, 4, 0], [0, 5, 6, 0], [0, 6, 5, 6], [0, 3, 6, 5]]]   // minor:  i-iv-v-i, i-bVI-bVII-i, i-bVII-bVI-bVII, i-iv-bVII-bVI
 @=> int allProgs[][][];
[[0, 3, 4, 3], [0, 5, 3, 4], [0, 4, 5, 3], [0, 3, 1, 4]] @=> int progs[][];
-99 => int REST; // rest marker in motif/bassLine (negative degrees are real notes)
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
        REST => motif[i];
        REST => bassLine[i];
        0 => delayThrow[i];
    }

    // --- CELL-BASED COMPOSITION (melodica lead) ---
    int cellDeg[3];
    int cellPos[3];

    0 => cellDeg[0];
    [1, 2, -1, 2, 1, -2] @=> int leaps[];
    leaps[s % leaps.cap()] => int leap1;
    leap1 => cellDeg[1];
    [-1, 0, 1, -1, 0] @=> int resolves[];
    cellDeg[1] + resolves[(s / 2) % resolves.cap()] => cellDeg[2];
    if(cellDeg[2] == cellDeg[1]) cellDeg[1] + 1 => cellDeg[2]; // no repeated note in the cell

    // Spacious reggae phrasing — room for the delay between notes
    [[0, 6, 12], [0, 8, 14], [0, 6, 10], [2, 8, 14], [0, 10, 14]] @=> int cellRhythms[][];
    cellRhythms[(s / 3) % cellRhythms.cap()] @=> int cR[];
    cR[0] => cellPos[0]; cR[1] => cellPos[1]; cR[2] => cellPos[2];

    s % 3 => int varType;

    // Bar 1: the cell (all three notes — establish the idea)
    for(0 => int i; i < 3; i++) cellDeg[i] => motif[cellPos[i]];
    1 => delayThrow[cellPos[2]];

    // Bar 2: cell varied (transpose up a 3rd / invert / retrograde)
    for(0 => int i; i < 3; i++) {
        if(varType == 0) cellDeg[i] + 2 => motif[16 + cellPos[i]];
        else if(varType == 1) 0 - cellDeg[i] => motif[16 + cellPos[i]];
        else cellDeg[2 - i] => motif[16 + cellPos[i]];
    }
    1 => delayThrow[16 + cellPos[2]];

    // Bar 3: cell twice — first a 3rd higher (compressed), then the original
    // with an approach note from below leading in
    cellDeg[0] + 2 => motif[32 + cellPos[0] / 2];
    cellDeg[1] + 2 => motif[32 + cellPos[1] / 2];
    cellDeg[0] - 1 => motif[32 + 7];  // approach note
    cellDeg[0] => motif[32 + 8];
    cellDeg[1] => motif[32 + 8 + cellPos[1] / 2];
    if(8 + cellPos[2] / 2 < 16) cellDeg[2] => motif[32 + 8 + cellPos[2] / 2];
    1 => delayThrow[32 + 8];

    // Bar 4: half the cell, then resolve to the root — always
    cellDeg[1] => motif[48 + cellPos[0]];
    0 => motif[56];
    1 => delayThrow[56]; // let the echo carry into the next chord

    // --- BASS LINE: the lead voice of reggae, built from the same cell ---
    // Degrees relative to the chord root. Root on the one, cell intervals as
    // passing tones on the off-beats, space everywhere else.
    // Bar 1: statement
    0 => bassLine[0]; cellDeg[1] => bassLine[6]; cellDeg[2] => bassLine[8]; 7 => bassLine[14];
    // Bar 2: same variation type as the lead
    if(varType == 0) {
        2 => bassLine[16]; cellDeg[1] + 2 => bassLine[22]; cellDeg[2] + 2 => bassLine[24]; 4 => bassLine[30];
    } else if(varType == 1) {
        0 => bassLine[16]; 0 - cellDeg[1] => bassLine[22]; 0 - cellDeg[2] => bassLine[24]; 0 => bassLine[30];
    } else {
        0 => bassLine[16]; cellDeg[2] => bassLine[22]; cellDeg[1] => bassLine[24]; 4 => bassLine[30];
    }
    // Bar 3: busier, mirrors the lead's development
    0 => bassLine[32]; cellDeg[1] => bassLine[35]; cellDeg[2] => bassLine[38];
    4 => bassLine[40]; 2 => bassLine[42]; 0 => bassLine[44];
    // Bar 4: simplify — roots; the step-14 pickup to the next chord is added at playback
    0 => bassLine[48]; 0 => bassLine[56];

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
// Reggae modes: sunshine major + mixolydian, roots dorian + natural minor.
// All seven-note so stacked thirds give real triads for skank/organ/bass.
[[0,2,4,5,7,9,11], [0,2,4,5,7,9,10], [0,2,3,5,7,9,10], [0,2,3,5,7,8,10]] @=> int scales[][];
// 0: major, 1: mixolydian, 2: dorian, 3: natural minor

// Scale degree -> MIDI. Handles negative degrees (approach notes, inversions)
// and centres the key (keys above F# sit below C) so registers stay put.
fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    scl.cap() => int n;
    degree / n => int oct;
    degree % n => int d;
    if(d < 0) { d + n => d; oct - 1 => oct; }
    key => int k;
    if(k > 6) k - 12 => k;
    return k + octave * 12 + scl[d] + oct * 12;
}

fun int foldR(int m, int lo, int hi) {
    while(m < lo) m + 12 => m;
    while(m > hi) m - 12 => m;
    return m;
}

// Degree offset for transposing a phrase to the chord: roots above the 4th
// go down so phrases stay near the tonic instead of climbing.
fun int chordOffset(int root) {
    if(root >= 4) return root - 7;
    return root;
}

fun int isDimDegree(int deg) {
    scales[scaleType] @=> int scl[];
    scl[(deg + 4) % 7] - scl[deg % 7] => int fifth;
    if(fifth < 0) fifth + 12 => fifth;
    return fifth == 6;
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
// Energy 3 switches to steppers (four on the floor) for drive.
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0]] @=> int kPat[][];

// ============ VELOCITY MAPS ============
// Kick: beat 3 is the one-drop — HARD. Everything else ghost-level.
[0.6, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.55, 0.0, 0.0, 0.0] @=> float kickVel[];
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
// One-drop hats: swung 8ths, off-beats accented; energy 3 adds 16th ghosts
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0],
 [1,0,1,1,1,0,1,0,1,0,1,1,1,0,1,1]] @=> int chPat[][];

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
// Envelope gives the bass its space — notes speak and stop, no drone.
TriOsc bassOsc1 => LPF bassF => ADSR bassEnv => Gain bassG => master;
TriOsc bassOsc2 => bassF;
SinOsc bassSub => bassEnv; // pure sub layer for weight
0.4 => bassOsc1.gain; 0.35 => bassOsc2.gain; 0.35 => bassSub.gain;
400.0 => bassF.freq; 0.8 => bassF.Q; // gentle filter, no resonance
bassEnv.set(6::ms, 350::ms, 0.6, 90::ms);
0.22 => bassG.gain;
0 => int bassHold;
400.0 => float bassFiltTarget;
0.0 => float bassDriftPhase;
// Bass also feeds reverb lightly
// bass routes through master to reverb
// reverb send via master bus

// ============ MELODICA / ORGAN LEAD ============
// SinOsc + TriOsc layered for a reedy, organ-like tone — NOT Rhodes, NOT FM
// Breathy, simple. Gets thrown into delay.
SinOsc ldSin1 => LPF ldF => ADSR ldEnv => Gain ldDry => master;
ldEnv.set(30::ms, 300::ms, 0.55, 260::ms);
0 => int ldHold;
SinOsc ldSin2 => ldF; // detuned pair
TriOsc ldTri1 => ldF;
TriOsc ldTri2 => ldF; // detuned pair
0.4 => ldSin1.gain; 0.35 => ldSin2.gain;
0.25 => ldTri1.gain; 0.2 => ldTri2.gain;
2200.0 => ldF.freq; 0.9 => ldF.Q;
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
// ORGAN BUBBLE: the pad voices are gated into short off-beat chords
TriOsc padOsc1 => LPF padF => ADSR orgEnv => Gain padG => master;
SinOsc padOsc2 => padF;
TriOsc padOsc3 => padF;
SinOsc padOct => padF; // drawbar-ish octave on the root
0.25 => padOsc1.gain; 0.3 => padOsc2.gain; 0.25 => padOsc3.gain; 0.12 => padOct.gain;
900.0 => padF.freq; 0.9 => padF.Q;
orgEnv.set(3::ms, 110::ms, 0.3, 45::ms);
0 => int orgGate;
0.0 => padG.gain;
0.0 => float padGainTarget;
900.0 => float padFiltTarget;
0 => int padLastDeg;
0.0 => float padLfoPhase;

// Pad feeds reverb heavily — dub reverb tails are essential
// pad routes through master to reverb
// reverb send via master bus

// ============ SKANK GUITAR ============
// Short, choppy chord hits on off-beats — the "chick-a chick-a" rhythm
// Filtered noise + TriOsc for percussive, muted guitar approximation
// Skank: sample-based if available, Mandolin fallback
// Synth skank: a real triad (3 detuned saw pairs) through a band-pass,
// chopped short, plus a little pick noise — the "chk" on 2 and 4.
SawOsc skV[6];
BPF skankBP => ADSR skankChop => HPF skankHP => LPF skankFilt => Gain skankG => master;
for(0 => int i; i < 6; i++) { skV[i] => skankBP; 0.11 => skV[i].gain; }
Noise skPick => HPF skPickHP => skankChop;
0.05 => skPick.gain; 3000.0 => skPickHP.freq;
1600.0 => skankBP.freq; 0.8 => skankBP.Q;
350.0 => skankHP.freq;
skankChop.set(1::ms, 70::ms, 0.0, 12::ms);
4500.0 => skankFilt.freq; 0.7 => skankFilt.Q;
0 => int skankGate;
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

// Skank on beats 2 and 4 (steps 4, 12); energy 3 adds the "chk-a" double on 13
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,1,0,0]] @=> int skankPat[][];
// Organ bubble: low chord on the "&", answer on the "a" at energy 3
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [0,0,1,1,0,0,1,1,0,0,1,1,0,0,1,1]] @=> int bubPat[][];

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
    if(f.open(statePath, FileIO.READ)) {
        Std.atoi(f.readLine()) => int newEnergy;
        Std.atoi(f.readLine()) => int newKey;
        Std.atoi(f.readLine()) => int newScale;
        Std.atoi(f.readLine()) => int newSeed;
        Std.atoi(f.readLine()) => int newTs;
        f.close();

        // A new tune waits for the phrase boundary (bar 15 -> 0) so phrases
        // finish; from silence, or the first time, it applies at once.
        newKey * 1000000 + newScale * 1000 + (newSeed % 1000) => int newSig;
        if(newTs > 0 && newSig != musicSig &&
           (musicSig < 0 || phraseBar == 15 || masterTarget < 0.01)) {
            newSig => musicSig;
            Math.srandom(newSeed * 7919 + newKey * 31 + newScale + 1);
        newKey % 12 => key;
        newScale % scales.cap() => scaleType;
        if(scaleType < 0) 0 => scaleType;
        newSeed % 256 => seed;
        newSeed % 2 => variant;
        for(0 => int qi; qi < 4; qi++)
            for(0 => int pj; pj < 4; pj++)
                allProgs[scaleType][qi][pj] => progs[qi][pj];
        seed % progs.cap() => progIdx;
        -1 => phraseBar; // the advance below lands it on bar 0
        0 => chordIdx;
        0 => phraseRepeat;
        for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
        progs[progIdx][0] => chordRoot;
        generateMotif();
        }

        if(newTs != lastEventTs && newTs > 0) {
            newTs => lastEventTs;

            // --- TRANSITION TRIGGERS ---
            if(transition == 0 && energy >= 1) {
                if(newEnergy >= 3 && energy < 3) {
                    // Big moment: riser into heavy drop
                    2 => transition;
                    2 => transitionBars; // short build: reggae does not do long EDM risers
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
// ============ NOW PLAYING (read by the Claude Code mod) ============
fun void writeNow() {
    if(nowPath == "") return;
    FileIO nf;
    if(!nf.open(nowPath, FileIO.WRITE)) return;
    "" => string sc;
    for(0 => int i; i < scales[scaleType].cap(); i++) {
        if(i > 0) "," +=> sc;
        scales[scaleType][i] + "" +=> sc;
    }
    "" => string pr;
    for(0 => int i; i < progs[progIdx].cap(); i++) {
        if(i > 0) "," +=> pr;
        progs[progIdx][i] + "" +=> pr;
    }
    0 => int lvl;
    if(phraseBar >= 0 && phraseBar < 16) arrangement[phraseBar] => lvl;
    0 => int on;
    if(masterTarget > 0.01) 1 => on;
    "" => string ar;
    for(0 => int i; i < 16; i++) {
        if(i > 0) "," +=> ar;
        arrangement[i] + "" +=> ar;
    }
    nf.write("genre reggae\n");
    nf.write("bpm " + (BPM $ int) + "\n");
    nf.write("tick " + stepCount + "\n");
    nf.write("energy " + energy + "\n");
    nf.write("key " + key + "\n");
    nf.write("seed " + seed + "\n");
    nf.write("scale " + sc + "\n");
    nf.write("prog " + pr + "\n");
    nf.write("chord " + chordIdx + "\n");
    nf.write("bar " + phraseBar + "\n");
    nf.write("level " + lvl + "\n");
    nf.write("arr " + ar + "\n");
    nf.write("playing " + on + "\n");
    nf.write("volume " + ((volume * 100.0) $ int) + "\n");
    nf.write("end\n");
    nf.close();
}

while(true) {
    stepCount % 16 => int s;
    if(s == 1) writeNow(); // after the bar boundary settled

    // ---- BAR BOUNDARY ----
    if(s == 0) {
        readState();
        FileIO vf;
        if(vf.open(volumePath, FileIO.READ)) {
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
                // Reggae: up a 4th (+3 degrees) — the plagal lift; skip if it lands diminished
                (progs[progIdx][subIdx] + 3) % 7 => int subRoot;
                if(!isDimDegree(subRoot)) subRoot => chordSub[subIdx];
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
                    20.0 + p * p * 450.0 => fxHPF.freq; // bass-led genre: thin it, never gut it
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
        0.02 + transitionStep * 0.0002 => float rGain;
        if(rGain > 0.045) 0.045 => rGain;
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

    // Chord tones for this bar (scale degrees stacked in thirds)
    chordOffset(chordRoot) => int cOff;
    scales[scaleType] @=> int curScl[];

    // ---- SKANK GUITAR (beats 2 and 4) ----
    if(skankGate) { skankChop.keyOff(); 0 => skankGate; }
    if(transition != 4 && energy >= 2 && skankPat[energy][s]) {
        if(useSkankSamples) {
            // Pitch the minor (Dm) or major (F) sample to the current chord
            note(chordRoot, 0) % 12 => int rootPc;
            if(rootPc < 0) rootPc + 12 => rootPc;
            curScl[(chordRoot + 2) % 7] - curScl[chordRoot % 7] => int third;
            if(third < 0) third + 12 => third;
            0 => int skIdx; 2 => int smpRoot;
            if(third == 4) { 1 => skIdx; 5 => smpRoot; }
            rootPc - smpRoot => int semis;
            while(semis > 5) semis - 12 => semis;
            while(semis < -6) semis + 12 => semis;
            Math.pow(2.0, semis / 12.0) => smpSkank[skIdx].rate;
            0 => smpSkank[skIdx].pos;
            0.20 + Math.random2f(0.0, 0.08) => smpSkankG.gain;
            if(s == 13) smpSkankG.gain() * 0.55 => smpSkankG.gain;
        } else {
            // Close-voiced triad around E4-E5, detuned pairs
            for(0 => int v; v < 3; v++) {
                foldR(note(chordRoot + v * 2, 5), 62, 74) => int m;
                Std.mtof(m) => float f;
                f * 0.998 => skV[v * 2].freq;
                f * 1.002 => skV[v * 2 + 1].freq;
            }
            // Brighter chop on beat 4, duller "a" double; filter moves with the phrase
            1400.0 + (phraseBar % 4) * 150.0 => float bp;
            if(s == 12) bp + 300.0 => bp;
            bp => skankBP.freq;
            0.50 => float skVel;
            if(energy >= 3) 0.56 => skVel;
            if(s == 13) skVel * 0.5 => skVel;
            skVel * (1.0 + ((seed * 17 + stepCount) % 100 - 50) / 1000.0) => skankG.gain;
            skankChop.keyOn();
            1 => skankGate;
        }
    }

    // ---- BASS (cell-derived reggae line, follows the chords) ----
    if(bassHold > 0) { bassHold - 1 => bassHold; if(bassHold == 0) bassEnv.keyOff(); }
    if(transition != 4 && energy >= 1 && arrLevel >= 1 && motifGenerated) {
        phraseStep % PHRASE_LEN => int bStep;
        bassLine[bStep] => int bDeg;
        bStep % 16 => int bLocal;
        // Energy 1: only the structural notes (one, the off-beat answer, beat 3)
        if(energy == 1 && bLocal != 0 && bLocal != 6 && bLocal != 8) REST => bDeg;
        // Bar 4 of each chord: walk up into the next chord's root from a step below
        if(bLocal == 14 && bStep >= 48 && energy >= 2) {
            (chordIdx + 1) % 4 => int nIdx;
            progs[progIdx][nIdx] => int nRoot;
            if(phraseBar < 15 && chordSub[nIdx] >= 0) chordSub[nIdx] => nRoot;
            if(phraseBar == 15) progs[progIdx][0] => nRoot;
            chordOffset(nRoot) - 1 - cOff => bDeg;
        }
        // Energy 3: occasional bass run up the chord at the end of a 2-chord span
        if(energy >= 3 && phraseBar % 8 == 7 && (seed + phraseBar + phraseRepeat) % 3 == 0) {
            [0, -1, 2, -1, 4, -1, 5, -1, 7, -1, 5, -1, 4, -1, 2, -1] @=> int run[];
            run[bLocal] => bDeg;
            if(bDeg < 0) REST => bDeg;
        }
        if(bDeg > REST) {
            foldR(note(cOff + bDeg, 3), 33, 57) => int bassMidi;
            Std.mtof(bassMidi) => float bFreq;
            bFreq => bassOsc1.freq;
            bFreq * 1.002 => bassOsc2.freq;
            bassDriftPhase + 0.0001 => bassDriftPhase;
            bassOsc2.freq() + Math.sin(bassDriftPhase) * 0.3 => bassOsc2.freq;
            bFreq => bassSub.freq;
            if(s % 4 != 0) 520.0 => bassFiltTarget; // off-beat pop
            else 300.0 => bassFiltTarget;           // downbeat round
            // Downbeats ring longer, passing tones are short
            if(s % 8 == 0) 4 => bassHold; else 2 => bassHold;
            if(s == 0) 0.45 => bassG.gain; else 0.38 => bassG.gain; // bass is the lead voice: as loud as the kick
            bassEnv.keyOn();
        }
    }

    // ---- ORGAN BUBBLE (chord voices, follows arrangement + phrase dynamics) ----
    if(transition != 4 && s == 0 && arrLevel >= 2) {
        Std.mtof(foldR(note(chordRoot, 4), 53, 65)) => padOsc1.freq;
        Std.mtof(foldR(note(chordRoot + 2, 4), 55, 67)) => padOsc2.freq;
        Std.mtof(foldR(note(chordRoot + 4, 4), 57, 69)) => padOsc3.freq;
        padOsc1.freq() * 2.0 => padOct.freq;
        // Detune for width
        padOsc1.freq() * 0.998 => padOsc1.freq;
        padOsc3.freq() * 1.002 => padOsc3.freq;
        // Organ dynamics follow phrase position: gentle, gentle, peak, pull back
        phraseBar % 4 => int barInChord;
        if(barInChord < 2) 0.18 => padGainTarget;
        else if(barInChord == 2) 0.26 => padGainTarget;
        else 0.12 => padGainTarget;
        if(energy >= 3) padGainTarget * 1.3 => padGainTarget;
        // Filter opens through the chord
        800.0 + barInChord * 180.0 => padFiltTarget;
    } else if(arrLevel < 2) {
        0.0 => padGainTarget;
    }
    if(orgGate) { orgEnv.keyOff(); 0 => orgGate; }
    if(transition != 4 && arrLevel >= 2 && bubPat[energy][s]) {
        orgEnv.keyOn();
        1 => orgGate;
    }

    // ---- MELODICA LEAD (cell motif, with delay throws) ----
    if(ldHold > 0) { ldHold - 1 => ldHold; if(ldHold == 0) ldEnv.keyOff(); }
    if(transition != 4 && motifGenerated && arrLevel >= 3) {
        motif[phraseStep % PHRASE_LEN] => int deg;
        // Motif variation per repetition
        phraseBar / 4 => int motifRep;
        if(motifRep == 1 && deg > REST && (seed + phraseStep) % 5 == 0) REST => deg;
        if(motifRep == 3 && deg > REST && phraseStep % 8 == 6) deg - 1 => deg;
        if(deg > REST) {
            // Only fold extremes — per-note folding would wreck the contour
            foldR(note(deg + cOff, 5), 50, 84) => int ldMidi;
            // Rep 2: bar-3 peak jumps an octave (if it stays singable)
            if(motifRep == 2 && phraseStep >= 32 && phraseStep < 48 && ldMidi + 12 <= 82) ldMidi + 12 => ldMidi;
            Std.mtof(ldMidi) => float ldFreq;
            ldFreq => ldSin1.freq;
            ldFreq * 1.003 => ldSin2.freq; // detune pair
            ldFreq => ldTri1.freq;
            ldFreq * 0.997 => ldTri2.freq; // detune pair
            // Slow pitch drift LFO
            ldDriftPhase + 0.0001 => ldDriftPhase;
            ldSin2.freq() + Math.sin(ldDriftPhase) * 0.5 => ldSin2.freq;

            // Velocity: bar 3 peaks, bar 4 pulls back
            phraseStep % 16 => int localStep;
            0.13 => float ldVel;
            if(localStep % 4 == 0) 0.17 => ldVel;
            else if(localStep % 2 == 0) 0.15 => ldVel;
            if(phraseStep >= 32 && phraseStep < 48) ldVel * 1.15 => ldVel;
            if(phraseStep >= 48) ldVel * 0.75 => ldVel;
            1800.0 + Math.random2f(0.0, 600.0) => ldFiltTarget; // reedy melodica
            ldVel => ldAmpTarget;
            ldEnv.keyOn();
            3 => ldHold;

            // DELAY THROW: send select notes to the delay
            if(delayThrow[phraseStep % PHRASE_LEN]) 0.5 => ldToDelay.gain;
            else 0.0 => ldToDelay.gain;
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
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.3 => ldAmpCurrent;
        ldAmpCurrent => ldDry.gain;

        // Pad filter sweep with LFO — slow, dark, breathing
        0.0015 => float padLfoRate;
        if(arrLevel >= 3) padLfoRate * 1.4 => padLfoRate;
        if(phraseBar % 4 == 2) padLfoRate * 1.3 => padLfoRate;
        if(phraseBar >= 12) padLfoRate * 0.7 => padLfoRate;
        padLfoPhase + padLfoRate => padLfoPhase;
        Math.sin(padLfoPhase) * 200.0 => float padLfoMod;
        padF.freq() + ((padFiltTarget + padLfoMod) - padF.freq()) * 0.012 => padF.freq;
        if(padFiltTarget > 600.0) padFiltTarget * 0.9998 => padFiltTarget;
        padG.gain() + (padGainTarget - padG.gain()) * 0.05 => padG.gain;
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
