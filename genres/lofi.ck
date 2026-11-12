// lofi.ck - Beatpilot Lo-fi / Chillhop Engine
// 85 BPM, mellow, jazzy, dusty

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
// Samples are optional — install with ./install-samples.sh
// Falls back to synthesis when samples/ doesn't exist
me.dir() + "/../samples/lofi/" => string smpDir;
0 => int useSamples;

// ============ CLOCK ============
85.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;
4 => int SUBSTEPS;
0.63 => float swingAmt; // heavy swing — lofi lives on shuffle
22::ms => dur snareLag;  // backbeat sits lazily behind the grid

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
// 0=none, 1=hpf_sweep, 2=reverb_wash, 3=delay_swell
0 => int fxType;
0 => int fxBar;
0 => int fxLen;

// ============ INTRO STATE (call to the dancefloor) ============
0 => int introActive;
0 => int introBar;
0 => int introLen;

// ============ SCALES (7-note modes, so stacked thirds give real chords) ============
// major, dorian, natural minor, lydian
[[0,2,4,5,7,9,11], [0,2,3,5,7,9,10], [0,2,3,5,7,8,10], [0,2,4,6,7,9,11]] @=> int scales[][];

// ============ PHRASE / CHORD PROGRESSION ============
// Scale-degree roots; each becomes a 7th/9th chord in the current mode.
[[1, 4, 0, 5],   // ii-V-I-vi
 [0, 5, 1, 4],   // I-vi-ii-V turnaround
 [3, 2, 1, 0],   // IV-iii-ii-I descending
 [5, 3, 0, 4],   // vi-IV-I-V (darker)
 [3, 4, 2, 5],   // IV-V-iii-vi "royal road"
 [0, 3, 2, 5]] @=> int progs[][]; // I-IV-iii-vi
0 => int progIdx;
0 => int chordIdx;
0 => int chordRoot;
0 => int phraseBar;
0 => int phraseRepeat;  // how many times the 16-bar phrase has cycled
int chordSub[4];        // chord substitution slots (-1 = no sub)
int chordPc[4];         // pitch classes of root, 3rd, 5th, 7th of the current chord
int voicing[4];         // keys voicing currently sounding (MIDI)
int nextVoicing[4];
0 => int pushed;        // keys anticipated this bar's chord at the end of the last bar
-1 => int keysChord;    // chord root the keys voicing was built for
60 => int leadAnchor;   // MIDI of the chord root in the lead register (voice-led)

// ============ LEAD MOTIF (4-bar phrase — sparse, melodic) ============
-99 => int REST;
64 => int PHRASE_LEN;
int motif[64];          // lead: degrees relative to the chord root (REST = rest)
int bassLine[64];       // bass: degrees relative to the chord root (REST = rest)
0 => int motifGenerated;
0 => int phraseStep;    // current position in the 64-step phrase (shared by bass + lead)
0 => int compType;      // keys comping rhythm
0 => int arrType;

// Arrangement mask: which bars (0-15) have which layers active
// 0=nothing, 1=bass + sparse keys, 2=bass + comping keys, 3=+ lead
int arrangement[16];

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    scl.cap() => int n;
    degree => int d;
    octave => int o;
    while(d < 0) { d + n => d; o - 1 => o; }
    return key + o * 12 + scl[d % n] + (d / n) * 12;
}

fun int pcOf(int m) { return ((m % 12) + 12) % 12; }

// Degree whose triad would be diminished gets swapped for a neighbour chord
// (except natural minor, where ii-half-diminished is the classic jazz ii).
fun int fixRoot(int r) {
    ((r % 7) + 7) % 7 => r;
    if(note(r + 4, 0) - note(r, 0) == 6 && scaleType != 2) (r + 5) % 7 => r;
    return r;
}

fun int chordAt(int bar) {
    bar / 4 => int ci;
    if(ci > 3) 3 => ci;
    if(ci < 0) 0 => ci;
    progs[progIdx][ci] => int r;
    if(chordSub[ci] >= 0) chordSub[ci] => r;
    return fixRoot(r);
}

fun void setChordPcs(int root) {
    pcOf(note(root, 0)) => chordPc[0];
    pcOf(note(root + 2, 0)) => chordPc[1];
    pcOf(note(root + 4, 0)) => chordPc[2];
    pcOf(note(root + 6, 0)) => chordPc[3];
}

// Rootless voicing (3rd, 5th, 7th, 9th — the bass has the root), choosing the
// inversion that moves the fewest semitones from the previous chord.
fun void buildVoicing(int root, int prev[], int out[]) {
    int pc[4];
    pcOf(note(root + 2, 0)) => pc[0];
    pcOf(note(root + 4, 0)) => pc[1];
    pcOf(note(root + 6, 0)) => pc[2];
    pcOf(note(root + 8, 0)) => pc[3];
    pcOf(note(root, 0)) => int rp;
    if(pcOf(pc[3] - rp) == 1) rp => pc[3]; // b9 would grind: double the root instead
    999999 => int best;
    int cand[4];
    for(0 => int r; r < 4; r++) {
        for(0 => int lo; lo < 2; lo++) {
            // lowest note in E3..D#4 (lo=0) or one octave lower window start
            52 + lo * 6 => int floorM;
            floorM + pcOf(pc[r] - floorM) => cand[0];
            for(1 => int i; i < 4; i++) {
                pc[(r + i) % 4] => int p;
                cand[i - 1] + 1 + pcOf(p - (cand[i - 1] + 1)) => cand[i];
            }
            if(cand[3] > 77) continue;
            0 => int cost;
            if(prev[0] > 0) {
                for(0 => int i; i < 4; i++) Std.abs(cand[i] - prev[i]) +=> cost;
            } else {
                Std.abs(cand[0] + cand[3] - 124) => cost;
            }
            // close semitone rubs between neighbouring voices sound muddy on Rhodes
            for(1 => int i; i < 4; i++) if(cand[i] - cand[i - 1] == 1) 8 +=> cost;
            if(cost < best) {
                cost => best;
                for(0 => int i; i < 4; i++) cand[i] => out[i];
            }
        }
    }
}

fun int isChordTone(int m) {
    for(0 => int i; i < 4; i++) if(pcOf(m) == chordPc[i]) return 1;
    return 0;
}

// Notes a semitone above a chord tone (the 11th over a major chord, b9s, b6
// over minor) are resolved down onto that chord tone.
fun int fixAvoid(int m) {
    if(isChordTone(m)) return m;
    for(0 => int i; i < 4; i++) {
        if(pcOf(m - chordPc[i]) == 1) return m - 1;
    }
    return m;
}


// On the beat the melody lands on a chord tone (or the 9th, a lofi colour)
fun int snapStrong(int m) {
    if(isChordTone(m) || pcOf(m - chordPc[0]) == 2) return m;
    if(isChordTone(m - 1)) return m - 1;
    if(isChordTone(m + 1)) return m + 1;
    if(isChordTone(m - 2)) return m - 2;
    return m + 2;
}

fun void setArrangement(int t) {
    if(t == 0) {
        // Build: sparse -> +comping keys -> +lead -> strip back
        [1,1,2,2, 2,2,3,3, 3,3,3,3, 2,2,1,1] @=> int arrA[];
        for(0 => int i; i < 16; i++) arrA[i] => arrangement[i];
    } else if(t == 1) {
        // Call-response: lead bars alternate with keys + bass
        [2,2,3,3, 2,2,3,3, 2,2,3,3, 3,3,2,1] @=> int arrB[];
        for(0 => int i; i < 16; i++) arrB[i] => arrangement[i];
    } else {
        // Full then strip: everything then breakdown
        [2,2,3,3, 3,3,3,3, 2,2,2,2, 1,1,2,2] @=> int arrC[];
        for(0 => int i; i < 16; i++) arrC[i] => arrangement[i];
    }
}

fun void generateMotif() {
    seed => int s;
    for(0 => int i; i < PHRASE_LEN; i++) { REST => motif[i]; REST => bassLine[i]; }

    // --- CELL-BASED COMPOSITION ---
    // A short 3-note cell, then repeated/transposed/varied. Degrees are relative
    // to the chord root, so the phrase moves with the harmony.
    int cellDeg[3];
    int cellPos[3];

    [0, 2, 4, 2, 0] @=> int starts[];         // start on root, 3rd or 5th
    starts[(s / 7) % starts.cap()] => cellDeg[0];
    [1, 2, -1, 2, 1, -2] @=> int leaps[];
    leaps[s % leaps.cap()] => int leap1;
    cellDeg[0] + leap1 => cellDeg[1];
    [-1, 0, 1, -1, 0] @=> int resolves[];
    resolves[(s / 2) % resolves.cap()] => int res;
    cellDeg[1] + res => cellDeg[2];

    // Cell rhythm: wide and lazy (odd steps land on the swung 16th)
    [[0, 4, 6], [0, 3, 6], [0, 4, 8], [2, 4, 7], [0, 6, 8]] @=> int cellRhythms[][];
    cellRhythms[(s / 3) % cellRhythms.cap()] @=> int cR[];
    cR[0] => cellPos[0]; cR[1] => cellPos[1]; cR[2] => cellPos[2];

    s % 3 => int varType; // 0=transpose up, 1=invert, 2=retrograde

    // --- Bar 1: the cell ---
    for(0 => int i; i < 3; i++) cellDeg[i] => motif[cellPos[i]];

    // --- Bar 2: the cell varied ---
    if(varType == 0) {
        for(0 => int i; i < 3; i++) cellDeg[i] + 2 => motif[16 + cellPos[i]];
    } else if(varType == 1) {
        cellDeg[0] => motif[16 + cellPos[0]];
        cellDeg[0] - leap1 => motif[16 + cellPos[1]];
        cellDeg[0] - leap1 - res => motif[16 + cellPos[2]];
    } else {
        for(0 => int i; i < 3; i++) cellDeg[2 - i] + 1 => motif[16 + cellPos[i]];
    }

    // --- Bar 3: the cell twice, first higher, then original with approach ---
    for(0 => int i; i < 3; i++) {
        cellPos[i] => int p;
        if(p > 7) 7 => p;
        cellDeg[i] + 2 => motif[32 + p];
    }
    cellDeg[0] - 1 => motif[32 + 9];       // approach note from below
    cellDeg[0] => motif[32 + 10];
    cellDeg[1] => motif[32 + 12];

    // --- Bar 4: half the cell, then resolve to the root and breathe ---
    cellDeg[1] => motif[48];
    cellDeg[0] + 1 => motif[51];
    0 => int home;
    if(cellDeg[0] >= 4) 7 => home;          // nearest root (octave above for high cells)
    home => motif[56];

    // --- BASS LINE: same cell intervals, locked to the kick (steps 0 and 10) ---
    0 => bassLine[0];  leap1 => bassLine[10];
    0 => bassLine[16];
    if(varType == 0) leap1 + 2 => bassLine[26];
    else if(varType == 1) 0 - leap1 => bassLine[26];
    else res + leap1 => bassLine[26];
    // Bar 3: busier, mirrors the lead's development
    0 => bassLine[32]; leap1 => bassLine[38]; leap1 + res => bassLine[42]; -1 => bassLine[46];
    // Bar 4: roots, resolving
    0 => bassLine[48]; 0 => bassLine[58];

    (s / 11) % 3 => compType;
    s % 3 => arrType;
    setArrangement(arrType);

    0 => phraseStep;
    1 => motifGenerated;
}

// ============ AUTO-EVOLUTION ============
0 => int autoSection;
0 => int autoSectionBar;
0 => int autoActive;

// ============ MASTER BUS + REVERB ============
Gain masterOut => HPF fxHPF => dac;
20.0 => fxHPF.freq; 0.7 => fxHPF.Q;
Gain master => Gain dryOut => masterOut;
0.0 => master.gain;
// Warm reverb — longer tails for lofi. The send is high-passed so kick and
// bass stay dry and tight; the feedback runs through the LPFs so tails darken.
master => HPF rvSend => blackhole;
220.0 => rvSend.freq;
rvSend => DelayL rv1 => Gain rvFb1 => LPF rvF1 => Gain rvMix => masterOut;
rvSend => DelayL rv2 => Gain rvFb2 => LPF rvF2 => rvMix;
rvSend => DelayL rv3 => Gain rvFb3 => LPF rvF3 => rvMix;
rvSend => DelayL rv4 => Gain rvFb4 => LPF rvF4 => rvMix;
rvF1 => rv3; rvF2 => rv4; rvF3 => rv1; rvF4 => rv2;
0.18::second => rv1.max; 0.1573::second => rv1.delay;
0.25::second => rv2.max; 0.2137::second => rv2.delay;
0.32::second => rv3.max; 0.2891::second => rv3.delay;
0.42::second => rv4.max; 0.3719::second => rv4.delay;
0.42 => rvFb1.gain; 0.40 => rvFb2.gain; 0.38 => rvFb3.gain; 0.36 => rvFb4.gain;
2000.0 => rvF1.freq; 1800.0 => rvF2.freq; 1500.0 => rvF3.freq; 1300.0 => rvF4.freq;
0.22 => rvMix.gain;
0.78 => dryOut.gain;

// ============ SAMPLE BUFFERS (optional — loaded if samples/ exists) ============
SndBuf smpKick => Gain smpKickG => master;
SndBuf smpSnare => Gain smpSnareG => master;
SndBuf smpSnareGhost => Gain smpSnareGhostG => master;
SndBuf smpHat => Gain smpHatG => master;
SndBuf smpHatOpen => Gain smpHatOpenG => master;
0.0 => smpKickG.gain; 0.0 => smpSnareG.gain; 0.0 => smpSnareGhostG.gain;
0.0 => smpHatG.gain; 0.0 => smpHatOpenG.gain;

// Try loading samples
FileIO smpTest;
if(smpTest.open(smpDir + "kick.wav", FileIO.READ)) {
    smpTest.close();
    smpKick.read(smpDir + "kick.wav");
    smpSnare.read(smpDir + "snare.wav");
    smpSnareGhost.read(smpDir + "snare_ghost.wav");
    smpHat.read(smpDir + "hat_closed.wav");
    smpHatOpen.read(smpDir + "hat_open.wav");
    smpKick.samples() => smpKick.pos;
    smpSnare.samples() => smpSnare.pos;
    smpSnareGhost.samples() => smpSnareGhost.pos;
    smpHat.samples() => smpHat.pos;
    smpHatOpen.samples() => smpHatOpen.pos;
    0.25 => smpKickG.gain; 0.20 => smpSnareG.gain; 0.10 => smpSnareGhostG.gain;
    0.15 => smpHatG.gain; 0.12 => smpHatOpenG.gain;
    1 => useSamples;
    <<< "Beatpilot [lofi]: samples loaded" >>>;
} else {
    <<< "Beatpilot [lofi]: no samples found, using synthesis" >>>;
}

// ============ VELOCITY MAPS ============
[1.0, 0.0, 0.5, 0.0, 0.9, 0.0, 0.4, 0.6, 0.95, 0.0, 0.8, 0.0, 0.85, 0.0, 0.55, 0.3] @=> float kickVel[];
[0.7, 0.25, 0.5, 0.25, 0.8, 0.25, 0.5, 0.3, 0.7, 0.25, 0.5, 0.25, 0.8, 0.3, 0.5, 0.35] @=> float hatVel[];

// ============ KICK (soft, round — sample-accurate envelope in its own shred) ============
SinOsc kickOsc => LPF kickLPF => Gain kickG => master;
0.0 => kickOsc.gain;
300.0 => kickLPF.freq;
0.5 => kickG.gain;
0 => int kickId;

fun void kickShred(float amp, int id) {
    0.0 => kickOsc.phase;
    for(0 => int i; i < 320; i++) {
        if(id != kickId) return; // a newer kick took over
        i / 1000.0 => float t;
        50.0 + 65.0 * Math.exp(-t * 30.0) => kickOsc.freq;
        amp * Math.exp(-t * 11.0) => kickOsc.gain;
        1::ms => now;
    }
    if(id == kickId) 0.0 => kickOsc.gain;
}

// Boom-bap: kick on 1 and the "and" of 3; energy 3 adds the lazy swung "a" of 2
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0],
 [1,0,0,0,0,0,0,1,0,0,1,0,0,0,0,0]] @=> int kPat[][];

// ============ SNARE (brushy) ============
Noise snN => BPF snBP => ADSR snEnv => Gain snG => master;
1900.0 => snBP.freq; 0.8 => snBP.Q;
snEnv.set(1::ms, 130::ms, 0.0, 60::ms);
0.0 => snG.gain;

fun void snareShred(float g, dur lag) {
    lag => now;
    g * 3.5 => snG.gain;
    snEnv.keyOn();
}
fun void snHit(float g, dur lag) {
    if(useSamples) snG.gain() * 0.3 => g;
    spork ~ snareShred(g, lag);
}

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0]] @=> int snPat[][];

// Ghost brush hits (odd steps = swung)
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1],
 [0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,1]] @=> int snGhost[][];

// ============ HATS (soft, shuffled) ============
Noise chN => BPF chBP => ADSR chEnv => Gain chG => master;
3500.0 => chBP.freq; 1.2 => chBP.Q;
chEnv.set(0.5::ms, 25::ms, 0.0, 10::ms);
0.03 => chG.gain;

fun void hatShred(float g, dur lag) {
    lag => now;
    g * 3.0 => chG.gain;
    chEnv.keyOn();
}
fun void chHit(float g) {
    spork ~ hatShred(g, Math.random2f(0.0, 8.0)::ms);
}

// 8ths; energy 3 adds swung 16th ghosts so the shuffle is audible
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0],
 [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0],
 [1,0,1,1,1,0,1,0,1,0,1,1,1,0,1,1]] @=> int chPat[][];

// ============ BASS (warm sine + soft triangle, plucked envelope) ============
SinOsc bassOsc => ADSR bassEnv => LPF bassFilt => Gain bassG => master;
TriOsc bassTri => bassEnv;
0.6 => bassOsc.gain;
0.12 => bassTri.gain;
bassEnv.set(6::ms, 350::ms, 0.55, 90::ms);
600.0 => bassFilt.freq; 1.0 => bassFilt.Q;
0.0 => bassG.gain;
0.0 => float bassAmpTarget;
0.0 => float bassAmpCurrent;
600.0 => float bassFiltTarget;
-1 => int bassOffStep;

// ============ KEYS (Rhodes chords, rolled, voice-led) ============
Rhodey kv[4];
LPF keyFilt => Gain keyG => master;
for(0 => int i; i < 4; i++) kv[i] => keyFilt;
2600.0 => keyFilt.freq; 0.6 => keyFilt.Q;
0.0 => keyG.gain;
0.0 => float keyAmpTarget;
0.0 => float keyAmpCurrent;
2600.0 => float keyFiltTarget;
0.0 => float keyLfoPhase;

fun void strumShred(int a, int b, int c, int d, float vel) {
    [a, b, c, d] @=> int v[];
    for(0 => int i; i < 4; i++) {
        Std.mtof(v[i]) => kv[i].freq;
        vel * (1.0 - i * 0.06) => kv[i].noteOn;
        Math.random2f(9.0, 16.0)::ms => now; // rolled, like a player's hand
    }
}
fun void strike(int v[], float vel) {
    spork ~ strumShred(v[0], v[1], v[2], v[3], vel);
}

// ============ LEAD (vibraphone above the Rhodes, quarter-note echo) ============
ModalBar ld => LPF ldFilt => Gain ldDry => master;
1 => ld.preset; // vibraphone
3200.0 => ldFilt.freq; 0.7 => ldFilt.Q;
0.0 => ldDry.gain;
3200.0 => float ldFiltTarget;
0.0 => float ldAmpTarget;
0.0 => float ldAmpCurrent;

// Lead delay: quarter note, darkened feedback
ldDry => DelayL ldDly => LPF ldDlyF => Gain ldDlyOut => master;
ldDlyF => Gain ldDlyFb => ldDly;
(stepDur * 8) => ldDly.max;
(stepDur * 4) => ldDly.delay; // quarter note delay
0.35 => ldDlyFb.gain;
0.40 => ldDlyOut.gain;
2200.0 => ldDlyF.freq; // darker delay for warmth

// ============ VINYL CRACKLE ============
// Sparse clicks + a whisper of hiss + turntable rumble, all very quiet
Impulse vinylImp => HPF vinylHP => Gain vinylG => master;
1500.0 => vinylHP.freq;
Noise vinylHiss => BPF vinylBP => vinylG;
5000.0 => vinylBP.freq; 0.6 => vinylBP.Q;
0.012 => vinylHiss.gain;
Noise vinylRumble => LPF vinylLPF => Gain vinylRumbleG => master;
90.0 => vinylLPF.freq; 1.0 => vinylLPF.Q;
0.0 => vinylG.gain;
0.0 => vinylRumbleG.gain;

fun void vinylShred() {
    while(true) {
        Math.random2f(25.0, 260.0)::ms => now;
        if(vinylG.gain() > 0.0) {
            Math.random2f(0.2, 1.0) => float a;
            if(Math.random2(0, 12) == 0) a * 2.0 => a; // occasional bigger pop
            if(Math.random2(0, 1)) -1.0 *=> a;
            a => vinylImp.next;
        }
    }
}
spork ~ vinylShred();

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
        newScale % 4 => scaleType;
        newSeed % 256 => seed;
        newSeed % 2 => variant;
        seed % progs.cap() => progIdx;
        -1 => phraseBar; // the advance below lands it on bar 0
        0 => chordIdx;
        0 => phraseRepeat;
        for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
        progs[progIdx][0] => chordRoot;
        0 => pushed;
        -1 => keysChord;
        generateMotif();
        }

        if(newTs != lastEventTs && newTs > 0) {
            newTs => lastEventTs;

            newEnergy => energy;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;

            // Coming back from silence? Maybe do a dramatic intro
            if(masterTarget < 0.01 && newEnergy >= 2) {
                if((seed + newSeed) % 2 == 0) {
                    1 => introActive;
                    0 => introBar;
                    if((seed * 3 + newSeed) % 2 == 0) 2 => introLen;
                    else 4 => introLen;
                    800.0 => fxHPF.freq;
                }
            }

            1.0 => masterTarget;

            // Cancel auto-evolution
            if(autoActive) {
                0 => autoActive;
                0 => autoSection;
                0 => autoSectionBar;
            }

            if(energy >= 1) {
                0.03 => vinylG.gain;
                0.002 => vinylRumbleG.gain;
            }
        }
    }
}

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
    nf.write("genre lofi\n");
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

// ============ MAIN SEQUENCER ============
while(true) {
    stepCount % 16 => int s;
    if(s == 1) writeNow(); // after the bar boundary settled

    if(s == 0) {
        readState();
        FileIO vf;
        if(vf.open(volumePath, FileIO.READ)) {
            Std.atoi(vf.readLine()) => int vol;
            vf.close();
            if(vol >= 0 && vol <= 100) vol / 100.0 => volume;
        }
        barsSinceEvent + 1 => barsSinceEvent;

        // Advance chord progression
        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) {
            0 => phraseBar;
            phraseRepeat + 1 => phraseRepeat;
            // Chord substitution: every 3rd phrase, surprise one chord
            for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
            if(phraseRepeat % 3 == 2 && energy >= 2) {
                (seed * 13 + phraseRepeat) % 4 => int subIdx;
                // Jazz sub: diatonic chord a 3rd up (I->iii, ii->IV, IV->vi)
                (progs[progIdx][subIdx] + 2) % 7 => chordSub[subIdx];
            }
            // Odd passes use a different layer plan so the track evolves
            if(motifGenerated) setArrangement((arrType + phraseRepeat) % 3);
        }
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        chordAt(phraseBar) => chordRoot;
        setChordPcs(chordRoot);

        // Energy decay
        if(barsSinceEvent > 8 && energy > 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 1) {
                0.0 => vinylG.gain;
                0.0 => vinylRumbleG.gain;
                0.0 => ldAmpTarget;
                0.0 => bassAmpTarget;
            }
        }

        // Fade out when idle — no auto-evolution, just graceful silence
        if(barsSinceEvent > 10 && energy == 0) {
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
                0.22 => rvMix.gain;
                0.42 => rvFb1.gain; 0.40 => rvFb2.gain;
            } else {
                introBar $ float / introLen $ float => float p;
                // HPF sweeps down: filtered → open
                800.0 * (1.0 - p) * (1.0 - p) + 20.0 => fxHPF.freq;
                // Reverb wash: spacey anticipation
                0.32 => rvMix.gain;
                0.48 => rvFb1.gain; 0.46 => rvFb2.gain;
            }
        }

        // ---- FX: occasional tension/release ----
        // Trigger at bar 12 (~40% chance), runs 4 bars to end of phrase
        if(fxType == 0 && energy >= 2 && motifGenerated && phraseBar == 12 && !introActive) {
            (seed * 7 + stepCount / 320) % 5 => int fxRoll;
            if(fxRoll <= 1) {
                fxRoll + 1 => fxType;
                0 => fxBar;
                4 => fxLen;
            } else if(fxRoll == 2) {
                3 => fxType;
                0 => fxBar;
                4 => fxLen;
            }
        }
        // FX progression
        if(fxType > 0) {
            fxBar + 1 => fxBar;
            if(fxBar > fxLen) {
                // Release — decays back below
                0 => fxType; 0 => fxBar;
            } else {
                fxBar $ float / fxLen $ float => float p; // 0.25 to 1.0
                if(fxType == 1) {
                    // HPF sweep: thins the mix, builds tension
                    20.0 + p * p * 800.0 => fxHPF.freq;
                } else if(fxType == 2) {
                    // Reverb wash: boost mix + feedback
                    0.22 + p * 0.12 => rvMix.gain;
                    0.42 + p * 0.10 => rvFb1.gain;
                    0.40 + p * 0.10 => rvFb2.gain;
                } else if(fxType == 3) {
                    // Delay feedback swell: echoes spiral
                    0.35 + p * 0.25 => ldDlyFb.gain;
                    0.40 + p * 0.25 => ldDlyOut.gain;
                }
            }
        }
        // FX release: restore base values when done
        if(fxType == 0 && !introActive) {
            // Smooth HPF back to 20Hz (done in substeps)
            if(rvMix.gain() > 0.23) rvMix.gain() * 0.95 + 0.22 * 0.05 => rvMix.gain;
            if(rvFb1.gain() > 0.43) rvFb1.gain() * 0.95 + 0.42 * 0.05 => rvFb1.gain;
            if(rvFb2.gain() > 0.41) rvFb2.gain() * 0.95 + 0.40 * 0.05 => rvFb2.gain;
            if(ldDlyFb.gain() > 0.36) ldDlyFb.gain() * 0.95 + 0.35 * 0.05 => ldDlyFb.gain;
            if(ldDlyOut.gain() > 0.41) ldDlyOut.gain() * 0.95 + 0.40 * 0.05 => ldDlyOut.gain;
        }
    }

    // ---- KICK (soft, with velocity + humanization) ----
    if(kPat[energy][s]) {
        ((seed * 17 + stepCount) % 100 - 50) / 1000.0 => float velDrift;
        if(useSamples) {
            0 => smpKick.pos;
            0.20 + 0.15 * (kickVel[s] + velDrift) => smpKickG.gain;
        }
        0.4 + 0.2 * (kickVel[s] + velDrift) => float kAmp;
        if(useSamples) kAmp * 0.3 => kAmp; // blend: quieter synth when samples active
        kickId + 1 => kickId;
        spork ~ kickShred(kAmp, kickId);
    }

    // ---- SNARE (brush + ghost, laid back behind the beat) ----
    if(snPat[energy][s]) {
        if(useSamples) {
            0 => smpSnare.pos;
            0.15 + 0.10 * hatVel[s] => smpSnareG.gain;
        }
        0.05 + 0.03 * hatVel[s] => float sg;
        if(energy == 1) sg * 0.7 => sg;
        snHit(sg, snareLag);
    } else if(snGhost[energy][s]) {
        if(useSamples) {
            0 => smpSnareGhost.pos;
            0.06 => smpSnareGhostG.gain;
        }
        snHit(0.02, snareLag);
    }

    // ---- HATS (with velocity + humanization) ----
    if(chPat[energy][s]) {
        ((seed * 13 + stepCount) % 100 - 50) / 1000.0 => float hVelDrift;
        if(useSamples) {
            0 => smpHat.pos;
            0.10 + 0.10 * (hatVel[s] + hVelDrift) => smpHatG.gain;
        }
        0.010 + 0.022 * (hatVel[s] + hVelDrift) => float hg;
        if(s % 2 == 1) hg * 0.5 => hg;           // swung 16th ghosts
        if(energy == 1) hg * 0.6 => hg;
        if(useSamples) hg * 0.3 => hg;
        chHit(hg);
    }

    // ---- DRUM MICRO-VARIATION (seed-deterministic per-bar mutations) ----
    if(energy >= 2) {
        (seed + phraseBar * 7) % 8 => int drumVar;
        // Extra ghost hat on an empty step
        if(drumVar < 3 && s == 5 && !chPat[energy][s]) chHit(0.010);
        // Extra ghost brush on an empty step
        if(drumVar >= 5 && s == 11 && !snPat[energy][s] && !snGhost[energy][s]) snHit(0.015, snareLag);
    }

    // ---- DRUM FILL (brush rolls at phrase boundaries) ----
    if(drumFill > 0 && energy >= 1) {
        if(drumFill == 2) {
            // Big fill (end of 16-bar phrase): brush roll builds through bar
            if(s >= 4 && s % 2 == 0 && !snPat[energy][s] && !snGhost[energy][s]) {
                snHit(0.02 + (s $ float) / 16.0 * 0.04, snareLag);
            }
            if(s >= 8 && !chPat[energy][s]) chHit(0.01 + (s $ float) / 16.0 * 0.02);
        } else {
            // Small fill (end of 4-bar chord): ghost brush flurry in last quarter
            if(s >= 13 && s % 2 == 1 && !snPat[energy][s] && !snGhost[energy][s]) {
                snHit(0.02 + (s - 12) / 8.0 * 0.02, snareLag);
            }
        }
    }

    // ---- ARRANGEMENT: determine what plays this bar ----
    0 => int arrLevel;
    if(motifGenerated) arrangement[phraseBar] => arrLevel;
    if(energy < 2) { if(arrLevel > 2) 2 => arrLevel; }
    if(energy == 0) { if(arrLevel > 1) 1 => arrLevel; }

    // ---- BASS (cell-derived, follows arrangement) ----
    if(phraseStep == bassOffStep) { bassEnv.keyOff(); -1 => bassOffStep; }
    if(energy >= 1 && arrLevel >= 1 && motifGenerated) {
        bassLine[phraseStep % PHRASE_LEN] => int bDeg;
        // Sparse bars: roots only on the downbeats
        if(arrLevel == 1 && phraseStep % 16 != 0) REST => bDeg;
        if(bDeg != REST) {
            // Chord root in B1..A#2, passing tones measured from it
            note(chordRoot, 2) => int rr;
            while(rr < 35) rr + 12 => rr;
            while(rr > 46) rr - 12 => rr;
            rr + note(chordRoot + bDeg, 2) - note(chordRoot, 2) => int bMidi;
            fixAvoid(bMidi) => bMidi;
            Std.mtof(bMidi) => bassOsc.freq;
            Std.mtof(bMidi) => bassTri.freq;
            bassEnv.keyOn();
            // Release just before the next bass note (max 6 steps)
            1 => int len;
            while(len < 6 && bassLine[(phraseStep + len) % PHRASE_LEN] == REST) len++;
            if(len > 1) len - 1 => len;
            (phraseStep + len) % PHRASE_LEN => bassOffStep;
            // Bass filter: gentle, opens slightly in bar 3
            if(phraseStep >= 32 && phraseStep < 48) {
                800.0 + Math.random2f(0.0, 200.0) => bassFiltTarget;
            } else {
                500.0 + Math.random2f(0.0, 100.0) => bassFiltTarget;
            }
            0.13 => bassAmpTarget;
        }
    } else {
        0.0 => bassAmpTarget;
    }

    // ---- KEYS (Rhodes, voice-led, comping rhythm, phrase dynamics) ----
    if(motifGenerated) {
        if(s == 0) {
            if(keysChord != chordRoot) {
                buildVoicing(chordRoot, voicing, nextVoicing);
                for(0 => int i; i < 4; i++) nextVoicing[i] => voicing[i];
                chordRoot => keysChord;
                0 => pushed; // the push guessed a different chord: strike the real one
            }
            // Keys dynamics follow phrase position: gentle, gentle, peak, pull back
            phraseBar % 4 => int barInChord;
            if(barInChord < 2) 0.04 => keyAmpTarget;
            else if(barInChord == 2) 0.07 => keyAmpTarget;
            else 0.03 => keyAmpTarget;
            if(energy >= 3) keyAmpTarget * 1.3 => keyAmpTarget;
            if(energy == 0) keyAmpTarget * 0.8 => keyAmpTarget;
            2000.0 + barInChord * 250.0 => keyFiltTarget;   // filter opens through the chord
            if(!pushed) strike(voicing, 0.55);
            0 => pushed;
        } else if(arrLevel >= 2) {
            // Comping: a softer re-strike, and the classic early "push" into the next chord
            (s == 10 && compType == 1) || (s == 6 && compType == 2) => int restrike;
            if(restrike) strike(voicing, 0.35);
            if(s == 14 && phraseBar % 4 == 3 && compType != 1) {
                chordAt((phraseBar + 1) % 16) => int nr;
                if(phraseBar == 15) progs[progIdx][0] => nr; // next phrase restarts; subs reset
                fixRoot(nr) => nr;
                if(nr != chordRoot) {
                    buildVoicing(nr, voicing, nextVoicing);
                    for(0 => int i; i < 4; i++) nextVoicing[i] => voicing[i];
                    nr => keysChord;
                    strike(voicing, 0.5);
                    1 => pushed;
                }
            }
        }
    }

    // ---- LEAD (cell motif, vibraphone, follows arrangement) ----
    if(motifGenerated && arrLevel >= 3) {
        motif[phraseStep % PHRASE_LEN] => int deg;
        // Motif variation: each repetition of the 4-bar motif gets subtle changes
        phraseBar / 4 => int motifRep;
        if(motifRep == 1 && deg != REST && (seed + phraseStep) % 5 == 0) REST => deg; // drop a note
        if(motifRep == 3 && deg != REST && phraseStep % 8 == 6) deg - 1 => deg; // approach from below
        if(deg != REST) {
            // Chord root in the lead register, chosen closest to the last one
            note(chordRoot, 5) => int lr;
            while(lr - leadAnchor > 6) lr - 12 => lr;
            while(leadAnchor - lr > 6) lr + 12 => lr;
            if(lr < 62) lr + 12 => lr;
            if(lr > 73) lr - 12 => lr;
            lr => leadAnchor;
            lr + note(chordRoot + deg, 5) - note(chordRoot, 5) => int ldMidi;
            if(motifRep == 2 && phraseStep >= 32 && phraseStep < 48 && ldMidi + 12 <= 86) ldMidi + 12 => ldMidi; // octave jump on peak
            fixAvoid(ldMidi) => ldMidi;
            if(phraseStep % 4 == 0) snapStrong(ldMidi) => ldMidi;
            Std.mtof(ldMidi) => ld.freq;
            // Velocity: phrase contour
            phraseStep % 16 => int localStep;
            0.45 => float ldVel;
            if(localStep % 4 == 0) 0.6 => ldVel;
            if(phraseStep >= 32 && phraseStep < 48) ldVel * 1.15 => ldVel;
            if(phraseStep >= 48) ldVel * 0.7 => ldVel;
            ldVel => ld.noteOn;
            2800.0 + Math.random2f(0.0, 600.0) => ldFiltTarget;
        }
        0.7 => ldAmpTarget;
    } else if(arrLevel < 3) {
        0.0 => ldAmpTarget;
    }

    // Advance phrase step (shared by bass + lead)
    if(motifGenerated) {
        phraseStep + 1 => phraseStep;
        if(phraseStep >= PHRASE_LEN) 0 => phraseStep;
    }

    // ---- SWING ----
    stepDur => dur thisStepDur;
    if(s % 2 == 0) {
        stepDur * 2.0 * swingAmt => thisStepDur;
    } else {
        stepDur * 2.0 * (1.0 - swingAmt) => thisStepDur;
    }

    // ---- SUBSTEP UPDATES ----
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        // Bass level + filter
        bassAmpCurrent + (bassAmpTarget - bassAmpCurrent) * 0.05 => bassAmpCurrent;
        bassAmpCurrent => bassG.gain;
        bassFilt.freq() + (bassFiltTarget - bassFilt.freq()) * 0.08 => bassFilt.freq;
        if(bassFiltTarget > 400.0) bassFiltTarget * 0.998 => bassFiltTarget;

        // Keys: filter LFO — Rhodes handles timbre, we just shape brightness
        // Dynamic LFO rate: faster during builds, slower during breakdowns
        0.0008 => float keyLfoRate;
        if(arrLevel >= 3) keyLfoRate * 1.4 => keyLfoRate;
        if(phraseBar % 4 == 2) keyLfoRate * 1.3 => keyLfoRate;
        if(phraseBar >= 12) keyLfoRate * 0.7 => keyLfoRate;
        keyLfoPhase + keyLfoRate => keyLfoPhase;
        keyAmpCurrent + (keyAmpTarget - keyAmpCurrent) * 0.008 => keyAmpCurrent;
        keyAmpCurrent * 4.5 => keyG.gain; // Rhodey output is quiet: bus make-up
        if(keyAmpTarget > 0.005) keyAmpTarget * 0.9992 => keyAmpTarget;
        Math.sin(keyLfoPhase) * 300.0 => float keyLfoMod;
        keyFilt.freq() + ((keyFiltTarget + keyLfoMod) - keyFilt.freq()) * 0.008 => keyFilt.freq;
        if(keyFiltTarget > 1600.0) keyFiltTarget * 0.99995 => keyFiltTarget;

        // Lead bus: fades in/out with the arrangement (the vibraphone decays itself)
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.03 => ldAmpCurrent;
        ldAmpCurrent => ldDry.gain;
        ldFilt.freq() + (ldFiltTarget - ldFilt.freq()) * 0.02 => ldFilt.freq;
        if(ldFiltTarget > 1600.0) ldFiltTarget * 0.999 => ldFiltTarget;

        // FX: smooth HPF back toward 20Hz when not active (skip during intro + HPF sweep)
        if(fxType != 1 && !introActive) fxHPF.freq() + (20.0 - fxHPF.freq()) * 0.04 => fxHPF.freq;

        // Master
        masterGain + (masterTarget - masterGain) * 0.015 => masterGain;
        masterGain * volume => master.gain;

        thisStepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
