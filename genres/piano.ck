// piano.ck - Beatpilot Neoclassical Piano Engine
// Slow, contemplative, sparse. Left-hand broken chords under a singing melody,
// with a sustain pedal that changes with the harmony.
// Inspired by Satie, Olafur Arnalds, Nils Frahm, Max Richter, Einaudi.
// Uses Salamander Grand Piano samples (CC0) when present, FM synthesis as fallback.

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
me.dir() + "/../samples/piano/" => string smpDir;
0 => int useSamples;

// ============ CLOCK ============
60.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;  // 16th note = 250ms
4 => int SUBSTEPS;
stepDur / SUBSTEPS => dur subDur;            // envelope update period (62.5ms)

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
// One chord per bar (4s at 60 BPM). A 16-bar phrase is A A' B A'':
// the A progression (progs) for bars 0-7 and 12-15, a contrasting B
// progression (progsB) for bars 8-11 that leaves the tonic and ends on the
// dominant, so the return of A at bar 12 feels like coming home.
[[0, 5, 3, 4],   // i-VI-iv-V (mournful)
 [0, 3, 4, 0],   // i-iv-v-i (resolved)
 [0, 4, 5, 3],   // i-v-VI-iv (Pachelbel-ish)
 [0, 2, 3, 5],   // i-III-iv-VI (ascending wash)
 [0, 5, 4, 3],   // descending bass line
 [0, 3, 5, 4]]   // unresolved swell
    @=> int progs[][];
[[3, 0, 5, 4],
 [5, 3, 0, 4],
 [5, 3, 0, 4],
 [3, 4, 5, 4],
 [3, 5, 0, 4],
 [5, 3, 1, 4]]
    @=> int progsB[][];
0 => int progIdx;
0 => int chordIdx;
0 => int chordRoot;
0 => int phraseBar;
0 => int phraseRepeat;

64 => int PHRASE_LEN;
-99 => int REST;
int motif[64];      // A melody (key scale degrees, 0 = tonic; REST = silence)
int motifB[64];     // B melody (contrasting section, bars 8-11)
int bassLine[64];   // bass passing tones (A section), REST = none
0 => int motifGenerated;
0 => int phraseStep;

// Arrangement: 0 = left hand alone, 1 = + melody, 2 = + melody in octaves
int arrangement[16];
[[0,0,0,0, 1,1,1,1, 2,2,2,2, 1,1,1,1],
 [1,1,1,1, 1,1,1,1, 2,2,2,2, 1,1,1,1],
 [1,1,1,1, 0,0,0,0, 2,2,2,2, 1,1,1,1]]
    @=> int arrTemplates[][];

// ============ SCALES ============
// 0: natural minor (default mournful)
// 1: dorian (jazzier minor — major 6th)
// 2: major (warm, Pachelbel)
// 3: melodic minor (raised 6 + 7 — modern classical)
// 4: harmonic minor (dramatic raised 7th)
[[0,2,3,5,7,8,10], [0,2,3,5,7,9,10], [0,2,4,5,7,9,11], [0,2,3,5,7,9,11], [0,2,3,5,7,8,11]]
    @=> int scales[][];
[0,2,3,5,7,8,10] @=> int natMinorScl[];
[0,2,3,5,7,9,10] @=> int dorianScl[];

fun int mod7(int x) { return ((x % 7) + 7) % 7; }

// Chord-scale: in harmonic/melodic minor the raised 7th belongs to the
// dominant (V, vii) only — over every other chord the melody and the chord use
// the lowered form, as in real minor-key writing (no B natural over Eb major).
fun int sclPc(int idx, int root) {
    mod7(root) => int r;
    if(r != 4 && r != 6) {
        if(scaleType == 4) return natMinorScl[idx];
        if(scaleType == 3) return dorianScl[idx];
    }
    return scales[scaleType][idx];
}

// Semitones above the tonic for any scale degree (negative degrees OK)
fun int degSemi(int deg, int root) {
    mod7(deg) => int i;
    (deg - i) / 7 => int o;
    return sclPc(i, root) + o * 12;
}

// Diminished triads (ii in minor, vi in dorian) sound wrong in this style:
// move such a chord up a step (ii -> III, vi -> bVII).
fun int fixRoot(int r) {
    mod7(r) => int rr;
    degSemi(rr + 4, rr) - degSemi(rr, rr) => int fifth;
    if(fifth == 6) return mod7(rr + 1);
    return rr;
}

// Legacy helper (degree in the plain scale, given octave)
fun int note(int degree, int octave) {
    if(degree < 0) return 0;
    return key + octave * 12 + degSemi(degree, chordRoot);
}

fun int isCT(int d, int r) {
    mod7(d - r) => int i;
    if(i == 0 || i == 2 || i == 4) return 1;
    return 0;
}

// Nearest chord tone of chord r to degree d; ties go in direction pref
fun int nearCT(int d, int r, int pref) {
    if(isCT(d, r)) return d;
    if(pref == 0) 1 => pref;
    for(1 => int k; k < 4; k++) {
        if(isCT(d + k * pref, r)) return d + k * pref;
        if(isCT(d - k * pref, r)) return d - k * pref;
    }
    return d;
}

// ============ MELODY COMPOSITION ============
// Cell rhythms (16th-step positions within a bar) — quarter/half-note pacing
[[0, 8, 12], [0, 6, 8], [0, 4, 8], [4, 8, 12], [0, 10, 12]] @=> int rhythms[][];

// Non-chord tones are only allowed on weak positions, short, and stepwise
// (passing / neighbour notes). Everything else snaps to a chord tone.
fun void snapPass(int arr[], int ch[]) {
    REST => int prev;
    for(0 => int i; i < 64; i++) {
        if(arr[i] == REST) continue;
        // keep the line in a singable range (about a 12th)
        while(arr[i] > 10) arr[i] - 7 => arr[i];
        while(arr[i] < -3) arr[i] + 7 => arr[i];
        arr[i] => int d;
        ch[i / 16] => int r;
        -1 => int nx;
        for(i + 1 => int j; j < 64 && nx < 0; j++) if(arr[j] != REST) j => nx;
        64 => int endI; if(nx >= 0) nx => endI;
        endI - i => int len;
        if(!isCT(d, r)) {
            0 => int stepwise;
            // a real step: one degree AND at most a whole tone (the augmented
            // 2nd of harmonic minor is a leap, not a passing step)
            if(prev != REST && Math.abs(d - prev) == 1 &&
               Math.abs(degSemi(d, r) - degSemi(prev, r)) <= 2) 1 => stepwise;
            if(nx >= 0 && Math.abs(arr[nx] - d) == 1 &&
               Math.abs(degSemi(arr[nx], r) - degSemi(d, r)) <= 2) 1 => stepwise;
            if(i % 8 == 0 || !stepwise || len > 4) {
                1 => int dir;
                if(prev != REST && d < prev) -1 => dir;
                nearCT(d, r, dir) => arr[i];
            }
        }
        arr[i] => prev;
    }
}

// One 4-bar section built from a 3-note cell:
// bar 1 = cell, bar 2 = varied cell (sequence / inversion / retrograde)
// anchored on the nearest chord tone, bar 3 = climax (cell up high, then an
// approach note from below), bar 4 = half the cell + cadence, held.
fun void composeSection(int arr[], int ch[], int start, int rhy, int lp, int rs, int vt, int cadTarget) {
    for(0 => int i; i < 64; i++) REST => arr[i];
    rhythms[rhy] @=> int R[];
    nearCT(start, ch[0], 1) => int d0;
    d0 + lp => int d1;
    d1 + rs => int d2;
    d0 => arr[R[0]]; d1 => arr[R[1]]; d2 => arr[R[2]];

    nearCT(d2, ch[1], -1) => int a;
    a + lp => int e1; e1 + rs => int e2;
    if(vt == 1) { a - lp => e1; e1 - rs => e2; }
    if(vt == 2) { a + (d1 - d2) => e1; a + (d0 - d2) => e2; }
    if(a == d0 && e1 == d1 && e2 == d2) { a - lp => e1; e1 - rs => e2; }  // never an exact repeat
    a => arr[16 + R[0]]; e1 => arr[16 + R[1]]; e2 => arr[16 + R[2]];

    d0 + 4 => int pkAim; if(pkAim > 9) 9 => pkAim;
    nearCT(pkAim, ch[2], 1) => int pk;
    if(pk - e2 > 5) nearCT(e2 + 4, ch[2], -1) => pk;
    lp => int l3;
    if(pk + l3 > 10 || pk + l3 < -2) -l3 => l3;
    pk => arr[32]; pk + l3 => arr[36]; pk + l3 + rs => arr[38];
    // step down from the climax into a chord tone, approached from below
    nearCT(pk + l3 + rs - 2, ch[2], -1) => int tg;
    tg - 1 => arr[42]; tg => arr[44];

    nearCT(cadTarget, ch[3], -1) => int cad;
    nearCT(cad + 2, ch[3], 1) => int pre;
    pre => arr[48]; cad => arr[56];
    snapPass(arr, ch);
}

fun void chooseArrangement() {
    arrTemplates[(seed + phraseRepeat) % arrTemplates.cap()] @=> int t[];
    for(0 => int i; i < 16; i++) t[i] => arrangement[i];
}

fun void generateMotif() {
    seed => int s;
    int chA[4]; int chB[4];
    for(0 => int i; i < 4; i++) {
        fixRoot(progs[progIdx][i]) => chA[i];
        fixRoot(progsB[progIdx][i]) => chB[i];
    }
    [2, 1, -1, 2, 3, -2] @=> int leaps[];
    leaps[s % leaps.cap()] => int leap1;
    [-1, 0, 1, -1, -2] @=> int resolves[];
    resolves[(s / 2) % resolves.cap()] => int res;
    [2, 4, 7, 4] @=> int starts[];
    starts[(s / 3) % starts.cap()] => int st;
    (s / 5) % rhythms.cap() => int rhy;
    (s / 7) % 3 => int vt;
    // A: cadence aims at the tonic. B: starts a 3rd higher, inverted cell,
    // different rhythm, and ends on a half cadence (degree 1 over V).
    composeSection(motif, chA, st, rhy, leap1, res, vt, 0);
    st + 2 => int stB; if(stB > 6) st => stB;
    composeSection(motifB, chB, stB, (rhy + 2) % rhythms.cap(), -leap1, -res, (vt + 1) % 3, 1);

    // Bass passing tone on beat 4 when the next root is a 3rd+ away and the
    // passing degree is a tone of the current chord (an inversion walk)
    for(0 => int i; i < 64; i++) REST => bassLine[i];
    for(0 => int b; b < 4; b++) {
        chA[b] => int r; chA[(b + 1) % 4] => int nr;
        nr - r => int dd;
        if(dd > 3) dd - 7 => dd;
        if(dd < -3) dd + 7 => dd;
        if(Math.abs(dd) >= 2) {
            1 => int sg; if(dd < 0) -1 => sg;
            nr - sg => int pass;
            if(isCT(pass, r)) pass => bassLine[b * 16 + 12];
        }
    }
    chooseArrangement();
    0 => phraseStep;
    1 => motifGenerated;
}

// ============ MASTER BUS + REVERB ============
Gain masterOut => HPF fxHPF => Dyno lim => dac;
20.0 => fxHPF.freq; 0.5 => fxHPF.Q;
lim.limit(); 0.85 => lim.thresh;   // safety only: piano peaks are spiky
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
0.55 => rvFb1.gain; 0.52 => rvFb2.gain; 0.50 => rvFb3.gain; 0.48 => rvFb4.gain;
2500.0 => rvF1.freq; 2200.0 => rvF2.freq; 2000.0 => rvF3.freq; 1800.0 => rvF4.freq;
0.43 => rvMix.gain;
1.0 => dryOut.gain;

// ============ PIANO SAMPLES (Salamander Grand Piano, CC0) ============
// 11 keyzones at v8 (medium-forte velocity layer):
// MIDI 36 (C2), 42 (F#2), 48 (C3), 54 (F#3), 60 (C4), 66 (F#4),
// 72 (C5), 78 (F#5), 84 (C6), 90 (F#6), 96 (C7)
// Two buffers per zone (round-robin) so notes in the same zone don't cut
// each other off; each has an envelope so the pedal can damp it.
[36, 42, 48, 54, 60, 66, 72, 78, 84, 90, 96] @=> int smpMidi[];
22 => int NUM_SMP;
SndBuf @ smpBuf[22];
Envelope @ smpEnv[22];
float smpAmp[22];
int smpDamp[22];
int smpRR[11];
for(0 => int i; i < NUM_SMP; i++) {
    SndBuf b; b @=> smpBuf[i];
    Envelope e; e @=> smpEnv[i];
    smpBuf[i] => smpEnv[i] => master;
    0.0 => smpEnv[i].value;
    0.0 => smpAmp[i];
}

FileIO smpTest;
if(smpTest.open(smpDir + "p60.wav", FileIO.READ)) {
    smpTest.close();
    for(0 => int i; i < NUM_SMP; i++) {
        smpDir + "p" + smpMidi[i / 2] + ".wav" => string path;
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

// ============ PIANO VOICES (FM fallback) ============
// Each voice: FM pair (1:1, slightly inharmonic) + octave and 3rd harmonics
// through an LPF that closes as the note decays, a 2-cent unison partner,
// a hammer click, and a two-stage, pitch-dependent decay (fast then slow,
// high notes die sooner) like a struck string. A sustain pedal (pedalChange)
// damps everything when the harmony changes. Amplitude runs through an
// Envelope so decay/damping steps are smooth ramps, not zipper steps.
16 => int NUM_VOICES;
SinOsc @ vCarr[16];
SinOsc @ vMod[16];
SinOsc @ vDetune[16];
SinOsc @ vHarm2[16];
SinOsc @ vHarm3[16];
LPF @ vFilt[16];
Envelope @ vEnv[16];
Noise @ vClick[16];
BPF @ vClickBP[16];
ADSR @ vClickEnv[16];
float vAmp[16];
float vModDepth[16];
float vFiltCutoff[16];
float vRestCut[16];
float vFreq[16];
float vHarm2Amp[16];
float vDecE[16];
float vDecL[16];
int vAge[16];
int vDamp[16];
int vMidi[16];
int vConn[16];      // 1 = patched into master (idle voices cost no CPU)

for(0 => int i; i < NUM_VOICES; i++) {
    SinOsc co; co @=> vCarr[i];
    SinOsc mo; mo @=> vMod[i];
    SinOsc de; de @=> vDetune[i];
    SinOsc h2; h2 @=> vHarm2[i];
    SinOsc h3; h3 @=> vHarm3[i];
    LPF lp; lp @=> vFilt[i];
    Envelope en; en @=> vEnv[i];
    Noise n; n @=> vClick[i];
    BPF bp; bp @=> vClickBP[i];
    ADSR ce; ce @=> vClickEnv[i];

    vMod[i] => vCarr[i];
    2 => vCarr[i].sync;
    vCarr[i] => vFilt[i] => vEnv[i];   // patched to master only while sounding
    vDetune[i] => vFilt[i];
    vHarm2[i] => vFilt[i];
    vHarm3[i] => vFilt[i];
    vClick[i] => vClickBP[i] => vClickEnv[i];

    0.35 => vCarr[i].gain;
    0.12 => vDetune[i].gain;
    0.0 => vMod[i].gain;
    0.0 => vHarm2[i].gain;
    0.0 => vHarm3[i].gain;
    0.8 => vFilt[i].Q;
    3000.0 => vFilt[i].freq;
    0.0 => vEnv[i].value;
    subDur => vEnv[i].duration;
    0.0 => vAmp[i];
    0.0 => vModDepth[i];
    0.0 => vHarm2Amp[i];
    3000.0 => vFiltCutoff[i];
    -1 => vMidi[i];

    0.0 => vClick[i].gain;
    1800.0 => vClickBP[i].freq;
    2.0 => vClickBP[i].Q;
    vClickEnv[i].set(0.3::ms, 5::ms, 0.0, 3::ms);
}

// Re-strike a key that is still sounding on its own voice (like a real
// piano string); otherwise take the quietest voice.
fun int allocVoice(int midi) {
    for(0 => int v; v < NUM_VOICES; v++) if(vMidi[v] == midi && vAmp[v] > 0.001) return v;
    0 => int best;
    100.0 => float bestA;
    for(0 => int v; v < NUM_VOICES; v++) {
        vAmp[v] => float a;
        if(vDamp[v]) a * 0.2 => a;
        if(a < bestA) { a => bestA; v => best; }
    }
    return best;
}

fun void triggerNote(int midi, float vel) {
    if(midi < 21 || midi > 108) return;
    if(useSamples) {
        nearestZone(midi) => int z;
        z * 2 + smpRR[z] => int b;
        1 - smpRR[z] => smpRR[z];
        Math.pow(2.0, (midi - smpMidi[z]) / 12.0) => smpBuf[b].rate;
        0 => smpBuf[b].pos;
        vel * 0.55 => smpAmp[b];
        0 => smpDamp[b];
        3::ms => smpEnv[b].duration;
        smpAmp[b] => smpEnv[b].target;
        return;
    }
    allocVoice(midi) => int v;
    if(!vConn[v]) { vEnv[v] => master; vClickEnv[v] => master; 1 => vConn[v]; }
    midi => vMidi[v];
    0 => vDamp[v];
    0 => vAge[v];
    Std.mtof(midi) => float f;
    f => vFreq[v];
    f => vCarr[v].freq;
    f * 1.0012 => vDetune[v].freq;          // ~2 cents: unison strings
    f * 1.001 => vMod[v].freq;
    f * (0.5 + vel * 1.2) => vModDepth[v];   // harder = brighter attack
    f * 2.002 => vHarm2[v].freq;             // stretched octave
    vel * 0.20 => vHarm2Amp[v];
    vHarm2Amp[v] => vHarm2[v].gain;
    f * 3.005 => vHarm3[v].freq;
    vHarm2Amp[v] * 0.45 => vHarm3[v].gain;
    f * (3.0 + vel * 4.0) => vFiltCutoff[v];
    if(vFiltCutoff[v] > 7000.0) 7000.0 => vFiltCutoff[v];
    vFiltCutoff[v] => vFilt[v].freq;
    f * 3.0 => vRestCut[v];
    if(vRestCut[v] < 350.0) 350.0 => vRestCut[v];
    // Two-stage decay in dB/s, faster for higher notes
    1.0 + (midi - 36) * 0.08 => float dl;
    if(dl < 0.9) 0.9 => dl;
    Math.pow(10.0, -dl / 20.0 / 16.0) => vDecL[v];
    Math.pow(10.0, -dl * 2.5 / 20.0 / 16.0) => vDecE[v];
    vel => vAmp[v];
    4::ms => vEnv[v].duration;
    vel => vEnv[v].target;
    vel * 0.14 => vClick[v].gain;
    f * 3.0 => vClickBP[v].freq;
    if(vClickBP[v].freq() > 4500.0) 4500.0 => vClickBP[v].freq;
    vClickEnv[v].keyOn();
}

fun void triggerBass(int midi, float vel) {
    triggerNote(midi, vel);
}

// Sustain pedal change: everything already sounding is damped
fun void pedalChange() {
    for(0 => int v; v < NUM_VOICES; v++) if(vAmp[v] > 0.0) 1 => vDamp[v];
    for(0 => int i; i < NUM_SMP; i++) if(smpAmp[i] > 0.0) 1 => smpDamp[i];
}

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
        newSeed % 256 => seed;
        seed % progs.cap() => progIdx;
        -1 => phraseBar; // the advance below lands it on bar 0
        0 => chordIdx;
        0 => phraseRepeat;
        progs[progIdx][0] => chordRoot;
        generateMotif();
        }

        if(newTs != lastEventTs && newTs > 0) {
            newTs => lastEventTs;

            newEnergy => energy;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;
            1.0 => masterTarget;
        }
    }
}

// ============ LEFT HAND ============
// lh[0] = bass, lh[1..3] = upper voices low -> high. Voicings are voice-led:
// each chord takes the inversion closest to the previous one, kept below
// the melody.
int lh[4];
0 => int barMelMask;   // pitch classes the melody uses in the current bar
int upPrev[3];
0 => int haveUpPrev;
-1 => int bassPrev;

[[0,1,2,3, 2,1,2,3], [0,2,1,3, 1,2,3,2], [0,1,3,2, 3,1,2,1]] @=> int pat8[][];
[[0,1,2,3, 1,2,3,2, 0,1,2,3, 2,3,1,2],
 [0,2,1,3, 2,1,3,1, 0,2,1,3, 2,1,3,2],
 [0,1,2,1, 3,1,2,1, 0,1,2,1, 3,2,1,2]] @=> int pat16[][];

fun int inB() { if(phraseBar >= 8 && phraseBar < 12) return 1; return 0; }

fun void buildVoicing(int melMin) {
    chordRoot => int r;
    (key + degSemi(r, r)) % 12 => int rpc;
    (key + degSemi(r + 2, r)) % 12 => int p0;
    (key + degSemi(r + 4, r)) % 12 => int p1;
    (key + degSemi(r + 6, r)) % 12 => int sev;
    (key + degSemi(r + 8, r)) % 12 => int nin;
    // colour tone candidates: 7th / add9 (order by seed; maj7 prefers add9),
    // then a doubled root. A colour a semitone from any melody note in this
    // bar, or a b9 over the root, is not allowed.
    int cand[3]; int cpen[3];
    sev => cand[0]; nin => cand[1];
    if((seed / 11) % 2 == 1 || ((sev - rpc) + 12) % 12 == 11) { nin => cand[0]; sev => cand[1]; }
    rpc => cand[2];
    0 => cpen[0]; 1 => cpen[1]; 3 => cpen[2];
    67 => int hi;
    if(melMin > 0 && melMin - 2 < hi) melMin - 2 => hi;
    if(hi < 58) 58 => hi;
    -1 => int bb; -1 => int b0; -1 => int b1; -1 => int b2; 100000 => int bc;
    // bass (chord root, E1..D3) and the three upper voices are chosen
    // together: least total motion from the previous chord, kept in register
    for(33 => int bs; bs <= 50; bs++) {
        if(bs % 12 != rpc) continue;
        0 => int bcost;
        if(bassPrev < 0) Math.abs(bs - 41) => bcost; else Math.abs(bs - bassPrev) => bcost;
        if(bs < 36) bcost + 4 => bcost;
        bs + 3 => int lo; if(lo < 47) 47 => lo;
        for(0 => int c; c < 3; c++) {
            cand[c] => int pc;
            if(c < 2) {
                if(((pc - rpc) + 12) % 12 == 1) continue;
                if(((barMelMask >> ((pc + 1) % 12)) & 1) || ((barMelMask >> ((pc + 11) % 12)) & 1)) continue;
            }
            for(lo => int x; x <= hi; x++) {
                if(x % 12 != p0) continue;
                for(lo => int y; y <= hi; y++) {
                    if(y % 12 != p1) continue;
                    for(lo => int z; z <= hi; z++) {
                        if(z % 12 != pc || z == x || z == y) continue;
                        int t[3]; x => t[0]; y => t[1]; z => t[2];
                        for(0 => int i; i < 2; i++) for(0 => int j; j < 2 - i; j++)
                            if(t[j] > t[j+1]) { t[j] => int tmp; t[j+1] => t[j]; tmp => t[j+1]; }
                        if(t[2] - t[0] > 15) continue;
                        if(t[1] - t[0] < 3 || t[2] - t[1] < 3) continue;  // no seconds in the LH
                        bcost + cpen[c] => int cost;
                        if(t[2] - t[0] > 12) cost + 2 => cost;
                        if(haveUpPrev) {
                            for(0 => int k; k < 3; k++) Math.abs(t[k] - upPrev[k]) +=> cost;
                        }
                        Math.abs(t[1] - 57) / 3 +=> cost;   // gravity: stay mid-register
                        if(cost < bc) { cost => bc; bs => bb; t[0] => b0; t[1] => b1; t[2] => b2; }
                    }
                }
            }
        }
    }
    if(bb < 0) {
        // fallback: root position triad above a C2-octave bass
        36 + (rpc + 12 - 0) % 12 => bb;
        bb + 12 + ((p0 - rpc) + 12) % 12 => b0;
        bb + 12 + ((p1 - rpc) + 12) % 12 => b1;
        bb + 24 => b2;
    }
    bb => bassPrev;
    bb => lh[0]; b0 => lh[1]; b1 => lh[2]; b2 => lh[3];
    b0 => upPrev[0]; b1 => upPrev[1]; b2 => upPrev[2];
    1 => haveUpPrev;
}

fun void rollUpper(float vel, int withBass) {
    if(withBass) { triggerBass(lh[0], vel * 1.2); 45::ms => now; }
    triggerNote(lh[1], vel);
    40::ms => now;
    triggerNote(lh[2], vel * 0.92);
    40::ms => now;
    triggerNote(lh[3], vel * 0.88);
}

// Phrase-level dynamics: A softer, B the high point, last bar dies away
fun float dynamics() {
    [0.85, 0.92, 1.10, 0.95] @=> float sec[];
    [0.96, 0.92, 1.08, 0.86] @=> float inBar[];
    sec[phraseBar / 4] * inBar[phraseBar % 4] => float d;
    if(phraseBar == 15) d * 0.85 => d;
    return d;
}

fun void playLeftHand(int s) {
    dynamics() => float dyn;
    ((seed * 17 + stepCount) % 100 - 50) / 1000.0 => float jit;
    if(energy == 0) {
        if(s == 0) spork ~ rollUpper(0.18 * dyn, 1);
        return;
    }
    if(energy == 1) {
        // Satie: bass on beat 1, soft rolled chord on beat 2
        if(s == 0) triggerBass(lh[0], (0.36 + jit) * dyn);
        if(s == 4) spork ~ rollUpper((0.20 + jit) * dyn, 0);
        if(s == 10 && phraseBar % 2 == 1) triggerNote(lh[2], (0.14 + jit) * dyn);
    } else {
        int idx;
        float v;
        if(energy == 2) {
            if(s % 2 == 1) return;
            pat8[(seed + inB()) % pat8.cap()][s / 2] => idx;
            0.20 => v;
        } else {
            pat16[(seed + inB()) % pat16.cap()][s] => idx;
            0.16 => v;
            if(s % 2 == 1) 0.13 => v;
        }
        if(s % 4 == 0) v + 0.03 => v;
        if(idx == 0) {
            0.34 => v;
            if(s != 0) 0.26 => v;
        }
        lh[idx] => int m;
        // bass passing tone into the next chord (A sections, beat 4)
        if(idx == 0 && s == 12 && !inB()) {
            bassLine[(phraseBar % 4) * 16 + 12] => int pd;
            if(pd != REST) {
                key + 36 + degSemi(pd, chordRoot) => int pm;
                while(pm - lh[0] > 6) pm - 12 => pm;
                while(lh[0] - pm > 6) pm + 12 => pm;
                pm => m;
            }
        }
        if(idx == 0) triggerBass(m, (v + jit) * dyn);
        else triggerNote(m, (v + jit) * dyn);
        if(energy == 3 && s == 0 && lh[0] - 12 >= 28) triggerBass(lh[0] - 12, 0.22 * dyn);
    }
}

// ============ RIGHT HAND (melody) ============
0 => int melTonic;
fun void setMelTonic() {
    key + 60 => melTonic;
    if(melTonic < 64) melTonic + 12 => melTonic;
}

fun int melMidi(int deg) { return melTonic + degSemi(deg, chordRoot); }

fun int barMelMin() {
    0 => barMelMask;
    motif @=> int arr[];
    if(inB()) motifB @=> arr;
    1000 => int mn;
    (phraseBar % 4) * 16 => int o;
    for(0 => int i; i < 16; i++) {
        arr[o + i] => int d;
        if(d != REST) {
            melMidi(d) => int m;
            if(m < mn) m => mn;
            barMelMask | (1 << (m % 12)) => barMelMask;
            if(phraseBar / 4 == 3 && melMidi(d - 1) < mn) melMidi(d - 1) => mn; // ornaments
        }
    }
    if(mn == 1000) return -1;
    return mn;
}

fun void playMelody(int s, int arrLevel) {
    motif @=> int arr[];
    if(inB()) motifB @=> arr;
    (phraseBar % 4) * 16 + s => int idx;
    idx => phraseStep;
    phraseBar / 4 => int rep;
    arr[idx] => int deg;
    0 => int grace;
    // rep 1 (A'): leave out one weak note — a question rather than a statement
    if(rep == 1 && deg != REST && s % 8 != 0 && (seed + idx + phraseRepeat) % 4 == 0) REST => deg;
    // rep 3 (A''): approach notes from a step below into selected notes
    if(rep == 3 && deg == REST && (s == 6 || s == 14) && idx + 2 < 64 && arr[idx + 2] != REST &&
       arr[idx + 1] == REST && arr[idx - 1] == REST && (seed + phraseBar + s / 8) % 2 == 0) {
        arr[idx + 2] - 1 => deg;
        1 => grace;
    }
    if(deg == REST) return;
    melMidi(deg) => int midi;
    [0.96, 0.92, 1.08, 0.88] @=> float inBar[];
    0.46 * dynamics() => float vel;
    if(s % 8 == 0) vel + 0.04 => vel;
    vel + (deg - 3) * 0.012 => vel;          // the line swells as it climbs
    if(grace) vel * 0.7 => vel;
    if(energy == 1) vel * 0.85 => vel;
    if(energy == 3) vel * 1.08 => vel;
    ((seed * 17 + stepCount) % 100 - 50) / 1000.0 + vel => vel;
    if(vel > 0.75) 0.75 => vel;
    if(vel < 0.15) 0.15 => vel;
    triggerNote(midi, vel);
    if(arrLevel >= 2 && !grace) {
        if(midi + 12 <= 93) triggerNote(midi + 12, vel * 0.55);
        else triggerNote(midi - 12, vel * 0.5);
    }
}

fun void computeChord() {
    phraseBar % 4 => chordIdx;
    progs[progIdx][chordIdx] => int raw;
    if(inB()) progsB[progIdx][chordIdx] => raw;
    // Substitution every 3rd pass through the phrase: in A' one inner chord
    // moves down a 3rd (shares two tones, so the melody still fits)
    if(phraseRepeat % 3 == 2 && phraseBar >= 4 && phraseBar < 8 &&
       chordIdx == 1 + (seed * 13 + phraseRepeat) % 2) raw - 2 => raw;
    fixRoot(raw) => chordRoot;
}

// ============ MAIN SEQUENCER ============
<<< "Beatpilot [piano]: ready" >>>;

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
    nf.write("genre piano\n");
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

    // Bar boundary
    if(s == 0) {
        readState();
        FileIO vf;
        if(vf.open(volumePath, FileIO.READ)) {
            Std.atoi(vf.readLine()) => int vol;
            vf.close();
            if(vol >= 0 && vol <= 100) vol / 100.0 => volume;
        }
        barsSinceEvent + 1 => barsSinceEvent;

        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) {
            0 => phraseBar;
            phraseRepeat + 1 => phraseRepeat;
            // Slow evolution: shift to a new progression every 3 cycles (~3 min)
            if(phraseRepeat % 3 == 0 && phraseRepeat > 0 && energy >= 1) {
                (seed + phraseRepeat * 7 + 19) % 256 => seed;
                seed % progs.cap() => progIdx;
                seed % scales.cap() => scaleType;
                generateMotif();
                <<< "Beatpilot [piano]: new movement" >>>;
            }
            chooseArrangement();
        }
        computeChord();

        // Energy decay
        if(barsSinceEvent > 8 && energy > 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
        }
        if(barsSinceEvent > 12 && energy == 0) 0.0 => masterTarget;

        // Pedal change with the harmony, then voice the new chord
        pedalChange();
        if(motifGenerated) {
            setMelTonic();
            buildVoicing(barMelMin());
        }
    }

    // ---- ARRANGEMENT ----
    0 => int arrLevel;
    if(motifGenerated) arrangement[phraseBar] => arrLevel;
    if(energy < 1) 0 => arrLevel;
    if(energy < 2 && arrLevel > 1) 1 => arrLevel;

    if(motifGenerated) {
        playLeftHand(s);
        if(arrLevel >= 1) playMelody(s, arrLevel);
    }

    // ---- SUBSTEP ENVELOPE UPDATES ----
    // Rubato: the last beat of each 4-bar phrase broadens, the end of the
    // 16-bar phrase slows down more (ritardando)
    stepDur => dur thisStepDur;
    if(phraseBar % 4 == 3 && s >= 12) thisStepDur * 1.08 => thisStepDur;
    if(phraseBar == 15 && s >= 8) thisStepDur * (1.0 + (s - 7) * 0.035) => thisStepDur;
    thisStepDur / SUBSTEPS => dur thisSub;
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        for(0 => int v; v < NUM_VOICES; v++) {
            if(vAmp[v] <= 0.0) continue;
            if(vAge[v] == 0) { 1 => vAge[v]; continue; }  // let the attack land
            vAge[v] + 1 => vAge[v];
            if(vDamp[v]) vAmp[v] * 0.72 => vAmp[v];
            else if(vAge[v] < 8) vAmp[v] * vDecE[v] => vAmp[v];
            else vAmp[v] * vDecL[v] => vAmp[v];
            if(vAmp[v] < 0.0005) {
                0.0 => vAmp[v]; -1 => vMidi[v];
                0.0 => vEnv[v].value;
                vEnv[v] =< master; vClickEnv[v] =< master; 0 => vConn[v];
                continue;
            }
            thisSub => vEnv[v].duration;
            vAmp[v] => vEnv[v].target;
            vModDepth[v] * 0.85 => vModDepth[v];
            vModDepth[v] => vMod[v].gain;
            vHarm2Amp[v] * vDecL[v] * 0.993 => vHarm2Amp[v];  // overtones fade first
            vHarm2Amp[v] => vHarm2[v].gain;
            vHarm2Amp[v] * 0.45 => vHarm3[v].gain;
            vFiltCutoff[v] + (vRestCut[v] - vFiltCutoff[v]) * 0.05 => vFiltCutoff[v];
            vFiltCutoff[v] => vFilt[v].freq;
        }
        for(0 => int i; i < NUM_SMP; i++) {
            if(smpAmp[i] <= 0.0 || !smpDamp[i]) continue;
            smpAmp[i] * 0.72 => smpAmp[i];
            if(smpAmp[i] < 0.0005) 0.0 => smpAmp[i];
            thisSub => smpEnv[i].duration;
            smpAmp[i] => smpEnv[i].target;
        }

        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain * volume => master.gain;

        thisSub => now;
    }

    stepCount + 1 => stepCount;
}
