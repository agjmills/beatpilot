// piano.ck - Beatpilot Neoclassical Piano Engine
// Slow, contemplative, sparse. Rolled chords with sustain pedal feel.
// Inspired by Satie, Olafur Arnalds, Nils Frahm, Max Richter.
// Uses Salamander Grand Piano samples (CC0) when present, FM synthesis as fallback.

// ============ SAMPLE DETECTION ============
me.dir() + "/../samples/piano/" => string smpDir;
0 => int useSamples;

// ============ CLOCK ============
60.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;  // 16th note = 250ms
4 => int SUBSTEPS;

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

// ============ PHRASE / SONG STRUCTURE ============
// Calmer progressions — neoclassical favors stepwise motion, modal cadences
[[0, 5, 3, 4],   // i-vi-iv-v (mournful)
 [0, 3, 4, 0],   // i-iv-v-i (resolved)
 [0, 4, 5, 3],   // i-v-vi-iv (Pachelbel-ish)
 [0, 2, 3, 5],   // i-iii-iv-vi (ascending wash)
 [0, 5, 4, 3],   // descending bass line
 [0, 3, 5, 4]]   // unresolved swell
    @=> int progs[][];
0 => int progIdx;
0 => int chordIdx;
0 => int chordRoot;
0 => int phraseBar;
0 => int phraseRepeat;

64 => int PHRASE_LEN;
int motif[64];
int bassLine[64];
0 => int motifGenerated;
0 => int phraseStep;

// Arrangement: 0=bass+chord, 1=+melody, 2=+countermelody (sparser slot grows)
int arrangement[16];

fun void generateMotif() {
    seed => int s;
    for(0 => int i; i < PHRASE_LEN; i++) -1 => motif[i];
    for(0 => int i; i < PHRASE_LEN; i++) -1 => bassLine[i];

    // Sparse cell — piano melody breathes, big gaps between notes
    int cellDeg[3];
    0 => cellDeg[0];
    [2, 1, 4, 2, -1, 3] @=> int leaps[];
    leaps[s % leaps.cap()] => int leap1;
    leap1 => cellDeg[1];
    [-1, 0, 1, -2, 0] @=> int resolves[];
    cellDeg[1] + resolves[(s / 2) % resolves.cap()] => cellDeg[2];

    // Bar 1: cell on beats 1, 3 of bar (very sparse)
    cellDeg[0] => motif[0];
    cellDeg[1] => motif[8];
    cellDeg[2] => motif[12];

    // Bar 2: cell varied — drop a 3rd, slower
    cellDeg[0] - 2 => motif[16];
    cellDeg[1] - 1 => motif[24];

    // Bar 3: development — countermelody with passing tones
    cellDeg[0] + 2 => motif[32];
    cellDeg[1] + 1 => motif[36];
    cellDeg[2] + 2 => motif[40];
    cellDeg[1] => motif[44];
    cellDeg[0] + 1 => motif[48];

    // Bar 4: resolve to root, Erik Satie style suspension
    cellDeg[2] => motif[52];
    cellDeg[1] => motif[56];
    0 => motif[60];

    // BASS: root pedal point, low octave, one note per chord
    // The bass is mostly sustained — only re-articulated on chord boundaries
    0 => bassLine[0];   // bar 1 chord 1
    0 => bassLine[16];  // bar 2 still chord 1
    0 => bassLine[32];  // bar 3 still chord 1
    0 => bassLine[48];  // bar 4 still chord 1

    // Arrangement: gradual unfolding
    s % 3 => int arrType;
    if(arrType == 0) {
        [0,0,1,1, 1,1,2,2, 2,2,2,2, 1,1,0,0] @=> int arrA[];
        for(0 => int i; i < 16; i++) arrA[i] => arrangement[i];
    } else if(arrType == 1) {
        [0,0,0,0, 1,1,1,1, 2,2,2,2, 1,1,1,0] @=> int arrB[];
        for(0 => int i; i < 16; i++) arrB[i] => arrangement[i];
    } else {
        [1,1,1,1, 2,2,2,2, 1,1,1,1, 2,2,1,0] @=> int arrC[];
        for(0 => int i; i < 16; i++) arrC[i] => arrangement[i];
    }

    0 => phraseStep;
    1 => motifGenerated;
}

// ============ MASTER BUS + REVERB ============
Gain masterOut => HPF fxHPF => dac;
20.0 => fxHPF.freq; 0.5 => fxHPF.Q;
Gain master => Gain dryOut => masterOut;
0.0 => master.gain;

// Multi-tap delay reverb — long, hall-like (piano needs serious sustain)
master => DelayL rv1 => Gain rvFb1 => LPF rvF1 => Gain rvMix => masterOut;
master => DelayL rv2 => Gain rvFb2 => LPF rvF2 => rvMix;
master => DelayL rv3 => Gain rvFb3 => LPF rvF3 => rvMix;
master => DelayL rv4 => Gain rvFb4 => LPF rvF4 => rvMix;
rvFb1 => rv3; rvFb2 => rv4; rvFb3 => rv1; rvFb4 => rv2;
0.18::second => rv1.max => rv1.delay;
0.23::second => rv2.max => rv2.delay;
0.31::second => rv3.max => rv3.delay;
0.41::second => rv4.max => rv4.delay;
// Bigger feedback for cathedral wash
0.55 => rvFb1.gain; 0.52 => rvFb2.gain; 0.50 => rvFb3.gain; 0.48 => rvFb4.gain;
2500.0 => rvF1.freq; 2200.0 => rvF2.freq; 2000.0 => rvF3.freq; 1800.0 => rvF4.freq;
0.32 => rvMix.gain;
0.70 => dryOut.gain;

// ============ SCALES ============
// 0: natural minor (default mournful)
// 1: dorian (jazzier minor — major 6th)
// 2: major (warm, Pachelbel)
// 3: melodic minor (raised 6 + 7 — modern classical)
// 4: harmonic minor (dramatic raised 7th)
[[0,2,3,5,7,8,10], [0,2,3,5,7,9,10], [0,2,4,5,7,9,11], [0,2,3,5,7,9,11], [0,2,3,5,7,8,11]]
    @=> int scales[][];

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    if(degree < 0) return 0;
    return key + octave * 12 + scl[degree % scl.cap()] + (degree / scl.cap()) * 12;
}

// ============ PIANO SAMPLES (Salamander Grand Piano, CC0) ============
// 11 keyzones at v8 (medium-forte velocity layer):
// MIDI 36 (C2), 42 (F#2), 48 (C3), 54 (F#3), 60 (C4), 66 (F#4),
// 72 (C5), 78 (F#5), 84 (C6), 90 (F#6), 96 (C7)
[36, 42, 48, 54, 60, 66, 72, 78, 84, 90, 96] @=> int smpMidi[];
SndBuf @ smpBuf[11];
Gain @ smpGain[11];
for(0 => int i; i < 11; i++) {
    SndBuf b; b @=> smpBuf[i];
    Gain g; g @=> smpGain[i];
    smpBuf[i] => smpGain[i] => master;
    0.0 => smpGain[i].gain;
}

FileIO smpTest;
if(smpTest.open(smpDir + "p60.wav", FileIO.READ)) {
    smpTest.close();
    for(0 => int i; i < 11; i++) {
        smpDir + "p" + smpMidi[i] + ".wav" => string path;
        smpBuf[i].read(path);
        smpBuf[i].samples() => smpBuf[i].pos;  // start silent
    }
    1 => useSamples;
    <<< "Beatpilot [piano]: Salamander samples loaded" >>>;
} else {
    <<< "Beatpilot [piano]: no samples found, using FM synthesis" >>>;
}

// Find nearest sample keyzone for a given MIDI note
fun int nearestZone(int midi) {
    0 => int best;
    1000 => int bestDist;
    for(0 => int i; i < 11; i++) {
        Math.abs(midi - smpMidi[i]) => int d;
        if(d < bestDist) { d => bestDist; i => best; }
    }
    return best;
}

// ============ PIANO VOICES (6-voice polyphony, FM fallback) ============
// Each voice: FM pair (carrier + modulator at 1:1 for piano-ish bright tone)
// + LPF that closes as the note decays + amplitude envelope
// + tiny detuned partner for thickness
// + noise click at attack for hammer
6 => int NUM_VOICES;
SinOsc @ vCarr[6];
SinOsc @ vMod[6];
SinOsc @ vDetune[6];
SinOsc @ vHarm2[6];   // octave harmonic — gives piano "ring"
SinOsc @ vHarm3[6];   // 3rd harmonic — mid bite
LPF @ vFilt[6];
Gain @ vGain[6];
Noise @ vClick[6];
BPF @ vClickBP[6];
ADSR @ vClickEnv[6];
float vAmp[6];
float vModDepth[6];
float vFiltCutoff[6];
float vFreq[6];
float vHarm2Amp[6];   // separate decay for harmonics (faster than fundamental)
0 => int nextVoice;

for(0 => int i; i < NUM_VOICES; i++) {
    SinOsc co; co @=> vCarr[i];
    SinOsc mo; mo @=> vMod[i];
    SinOsc de; de @=> vDetune[i];
    SinOsc h2; h2 @=> vHarm2[i];
    SinOsc h3; h3 @=> vHarm3[i];
    LPF lp; lp @=> vFilt[i];
    Gain g; g @=> vGain[i];
    Noise n; n @=> vClick[i];
    BPF bp; bp @=> vClickBP[i];
    ADSR ce; ce @=> vClickEnv[i];

    // Wire FM: mod modulates carrier (sync 2 = phase mod)
    vMod[i] => vCarr[i];
    2 => vCarr[i].sync;
    // Carrier + detuned partner + harmonics through filter
    vCarr[i] => vFilt[i] => vGain[i] => master;
    vDetune[i] => vFilt[i];
    vHarm2[i] => vFilt[i];
    vHarm3[i] => vFilt[i];
    // Click into gain (post-filter — we want the click bright)
    vClick[i] => vClickBP[i] => vClickEnv[i] => vGain[i];

    0.35 => vCarr[i].gain;
    0.12 => vDetune[i].gain;
    0.0 => vMod[i].gain;
    0.0 => vHarm2[i].gain;
    0.0 => vHarm3[i].gain;
    1.0 => vFilt[i].Q;
    3000.0 => vFilt[i].freq;
    0.0 => vGain[i].gain;
    0.0 => vAmp[i];
    0.0 => vModDepth[i];
    0.0 => vHarm2Amp[i];
    3000.0 => vFiltCutoff[i];

    // Click setup: shorter, more "thump" than "tick"
    0.4 => vClick[i].gain;
    1800.0 => vClickBP[i].freq;
    2.0 => vClickBP[i].Q;
    vClickEnv[i].set(0.3::ms, 5::ms, 0.0, 3::ms);
}

fun void triggerNote(int midi, float vel) {
    if(useSamples) {
        nearestZone(midi) => int z;
        Math.pow(2.0, (midi - smpMidi[z]) / 12.0) => float rate;
        rate => smpBuf[z].rate;
        0 => smpBuf[z].pos;
        vel * 0.55 => smpGain[z].gain;
        return;
    }
    // Round-robin allocation
    nextVoice => int v;
    (nextVoice + 1) % NUM_VOICES => nextVoice;
    Std.mtof(midi) => float f;
    f => vFreq[v];
    f => vCarr[v].freq;
    // Slightly detuned partner for chorus thickness
    f * 1.003 => vDetune[v].freq;
    // FM mod ratio: slightly inharmonic (real piano strings are slightly stiff)
    f * 1.001 => vMod[v].freq;
    // Initial mod depth — softer than before (less FM bite, more body)
    f * (0.6 + vel * 1.0) => vModDepth[v];
    // Octave harmonic — adds piano "ring", decays faster than fundamental
    f * 2.002 => vHarm2[v].freq;  // very slight inharmonicity (stretched octave)
    vel * 0.18 => vHarm2[v].gain;
    vel * 0.18 => vHarm2Amp[v];
    // 3rd harmonic — gives mid bite, decays even faster
    f * 3.005 => vHarm3[v].freq;
    vel * 0.08 => vHarm3[v].gain;
    // Filter opens lower than before — less synthy zip
    f * 4.0 => vFiltCutoff[v];
    if(vFiltCutoff[v] > 6500.0) 6500.0 => vFiltCutoff[v];
    vel * 1.0 => vAmp[v];
    // Hammer click — softer
    vel * 0.18 => vClick[v].gain;
    f * 3.0 => vClickBP[v].freq;
    if(vClickBP[v].freq() > 4500.0) 4500.0 => vClickBP[v].freq;
    vClickEnv[v].keyOn();
}

// ============ BASS PIANO (separate, lower, longer-decay voice) ============
SinOsc bassMod => SinOsc bassCarr => LPF bassFilt => Gain bassG => master;
2 => bassCarr.sync;
0.45 => bassCarr.gain;
0.0 => bassMod.gain;
1.0 => bassFilt.Q;
600.0 => bassFilt.freq;
0.0 => bassG.gain;
0.0 => float bassAmp;
0.0 => float bassModDepth;
600.0 => float bassFiltCutoff;

fun void triggerBass(int midi, float vel) {
    if(useSamples) {
        nearestZone(midi) => int z;
        Math.pow(2.0, (midi - smpMidi[z]) / 12.0) => float rate;
        rate => smpBuf[z].rate;
        0 => smpBuf[z].pos;
        vel * 0.7 => smpGain[z].gain;
        return;
    }
    Std.mtof(midi) => float f;
    f => bassCarr.freq;
    f => bassMod.freq;
    f * (1.0 + vel * 1.5) => bassModDepth;
    f * 5.0 => bassFiltCutoff;
    vel => bassAmp;
}

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
            seed % progs.cap() => progIdx;
            0 => phraseBar;
            0 => chordIdx;
            0 => phraseRepeat;
            progs[progIdx][0] => chordRoot;
            generateMotif();

            newEnergy => energy;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;
            1.0 => masterTarget;
        }
    }
}

// ============ ROLLED CHORD PLAYER ============
// On chord change, play 4-note chord rolled over ~120ms — that "shimmer" sound
fun void rollChord(int rootDeg, int oct, float vel) {
    // Root, 3rd, 5th, 7th from current scale
    triggerNote(note(rootDeg, oct), vel);
    30::ms => now;
    triggerNote(note(rootDeg + 2, oct), vel * 0.85);
    30::ms => now;
    triggerNote(note(rootDeg + 4, oct), vel * 0.8);
    30::ms => now;
    triggerNote(note(rootDeg + 6, oct), vel * 0.75);
}

// ============ MAIN SEQUENCER ============
<<< "Beatpilot [piano]: ready" >>>;

while(true) {
    stepCount % 16 => int s;

    // Bar boundary
    if(s == 0) {
        readState();
        FileIO vf;
        if(vf.open("/tmp/beatpilot-volume", FileIO.READ)) {
            Std.atoi(vf.readLine()) => int vol;
            vf.close();
            if(vol >= 0 && vol <= 100) vol / 100.0 => volume;
        }
        barsSinceEvent + 1 => barsSinceEvent;

        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) {
            0 => phraseBar;
            phraseRepeat + 1 => phraseRepeat;
            // Slow evolution: shift to a new progression every 4 cycles
            if(phraseRepeat % 4 == 0 && phraseRepeat > 0 && energy >= 1) {
                (seed + phraseRepeat * 7 + 19) % 256 => seed;
                seed % progs.cap() => progIdx;
                seed % scales.cap() => scaleType;
                progs[progIdx][0] => chordRoot;
                generateMotif();
                <<< "Beatpilot [piano]: new movement" >>>;
            }
        }
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        progs[progIdx][chordIdx] => chordRoot;

        // Energy decay
        if(barsSinceEvent > 8 && energy > 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
        }
        if(barsSinceEvent > 12 && energy == 0) 0.0 => masterTarget;

        // CHORD CHANGE: roll the chord. Happens once every 4 bars.
        if(motifGenerated && energy >= 1 && phraseBar % 4 == 0 && phraseBar < 16) {
            // Roll happens in a spork so the sequencer keeps ticking
            spork ~ rollChord(chordRoot, 4, 0.5 + energy * 0.1);
            // Bass note on chord root, low octave
            triggerBass(note(chordRoot, 2), 0.7);
        }
    }

    // ---- ARRANGEMENT ----
    0 => int arrLevel;
    if(motifGenerated) arrangement[phraseBar] => arrLevel;
    if(energy < 1) 0 => arrLevel;
    if(energy < 2 && arrLevel > 1) 1 => arrLevel;

    // ---- MELODY (only at arrLevel >= 1, very sparse) ----
    if(motifGenerated && arrLevel >= 1) {
        motif[phraseStep % PHRASE_LEN] => int deg;
        if(deg >= 0) {
            (deg + chordRoot) => int actualDeg;
            5 => int oct;
            // Bar 3 development can climb an octave
            if(arrLevel >= 2 && phraseStep >= 32 && phraseStep < 48) 6 => oct;
            note(actualDeg, oct) => int midi;
            // Velocity contour: bar 3 peaks, bar 4 pulls back
            phraseBar % 4 => int barInChord;
            0.3 => float vel;
            if(barInChord == 2) 0.4 => vel;
            if(barInChord == 3) 0.25 => vel;
            // Per-note humanization (-15% to +15%)
            ((seed * 17 + stepCount) % 60 - 30) / 200.0 + vel => vel;
            if(vel > 0.6) 0.6 => vel;
            if(vel < 0.15) 0.15 => vel;
            triggerNote(midi, vel);
        }
    }

    // Advance phrase step
    if(motifGenerated) {
        phraseStep + 1 => phraseStep;
        if(phraseStep >= PHRASE_LEN) 0 => phraseStep;
    }

    // ---- SUBSTEP ENVELOPE UPDATES ----
    stepDur => dur thisStepDur;
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        // Per-voice decay: amplitude, mod depth, filter, harmonics
        for(0 => int v; v < NUM_VOICES; v++) {
            // Slow exponential decay — piano sustain
            vAmp[v] * 0.998 => vAmp[v];
            vAmp[v] => vGain[v].gain;
            // Mod depth decays fast (hammer attack only)
            vModDepth[v] * 0.90 => vModDepth[v];
            vModDepth[v] => vMod[v].gain;
            // Octave harmonic decays faster than fundamental — piano "ring"
            vHarm2Amp[v] * 0.992 => vHarm2Amp[v];
            vHarm2Amp[v] => vHarm2[v].gain;
            vHarm2Amp[v] * 0.5 => vHarm3[v].gain;  // 3rd harmonic decays alongside
            // Filter closes more aggressively — kills the synthy brightness fast
            vFreq[v] * 1.2 => float restingCutoff;
            vFiltCutoff[v] + (restingCutoff - vFiltCutoff[v]) * 0.04 => vFiltCutoff[v];
            vFiltCutoff[v] => vFilt[v].freq;
        }

        // Bass voice decay
        bassAmp * 0.9985 => bassAmp;
        bassAmp => bassG.gain;
        bassModDepth * 0.93 => bassModDepth;
        bassModDepth => bassMod.gain;
        bassFiltCutoff + (300.0 - bassFiltCutoff) * 0.015 => bassFiltCutoff;
        bassFiltCutoff => bassFilt.freq;

        // Master gain
        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain * volume => master.gain;

        thisStepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
