// dub.ck - Beatpilot Dub Engine
// Deep, spacious dub with one-drop rhythm, massive delay throws, and heavy sub bass.
// Inspired by Lee "Scratch" Perry, King Tubby. The FX ARE the instrument.
// Reads state from <run dir>/state (see lib/paths.sh), written by the adapters or the mod.
// Energy (0-3) controls layer density and delay throw intensity.

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
me.dir() + "/../samples/dub/" => string smpDir;
0 => int useSamples;

// ============ CLOCK ============
70.0 => float BPM; // slower than reggae — heavy, ponderous
(60.0 / BPM / 4.0)::second => dur stepDur;
4 => int SUBSTEPS;
0.55 => float swingAmt; // straighter — dub is more hypnotic than groovy

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
// Progression degrees index the 7-note harmony scale (hScales) — see realChord()
// i-iv vamp, i-bVII-iv-i, i-bVI-iv-bVII, i-iv-bVI-v
[[0, 3, 0, 3], [0, 6, 3, 0], [0, 5, 3, 6], [0, 3, 5, 4]] @=> int progs[][];
0 => int progIdx;
0 => int chordIdx;
0 => int chordRoot;
0 => int phraseBar;
0 => int phraseRepeat;
int chordSub[4];

// ============ SCALES ============
// Melody/bass scales: minor pentatonic, phrygian, harmonic minor, natural minor
[[0,3,5,7,10], [0,1,3,5,7,8,10], [0,2,3,5,7,8,11], [0,2,3,5,7,8,10]] @=> int scales[][];
// Harmony scales (7-note parent each chord is stacked in) — pentatonic borrows aeolian
[[0,2,3,5,7,8,10], [0,1,3,5,7,8,10], [0,2,3,5,7,8,11], [0,2,3,5,7,8,10]] @=> int hScales[][];

// Floor division / modulo that behave for negative degrees (below the root)
fun int fDiv(int a, int b) { if(a >= 0) return a / b; return -((-a + b - 1) / b); }
fun int fMod(int a, int b) { return a - fDiv(a, b) * b; }

// Map a progression degree onto a real triad for the current scale:
// no diminished/augmented chords, and pentatonic roots must be pentatonic notes
fun int realChord(int d) {
    fMod(d, 7) => d;
    if(scaleType == 0) { if(d == 5) return 2; if(d == 1) return 4; }   // bVI -> bIII, ii° -> v
    if(scaleType == 1) { if(d == 4) return 1; if(d == 2) return 5; }   // v° -> bII (phrygian dread)
    if(scaleType == 2) { if(d == 6) return 4; if(d == 2) return 5; if(d == 1) return 4; } // vii°/III+/ii° -> V/VI
    if(scaleType == 3) { if(d == 1) return 4; }
    return d;
}
// Semitone (above key) of harmony-scale degree d
fun int hSemi(int d) { hScales[scaleType] @=> int h[]; return h[fMod(d, 7)] + 12 * fDiv(d, 7); }
// Semitone of melody-scale degree d (any sign)
fun int mSemi(int d) { scales[scaleType] @=> int scl[]; return scl[fMod(d, scl.cap())] + 12 * fDiv(d, scl.cap()); }
// Melody-scale index of the current chord root, folded so chords above a tritone sit below the tonic
fun int rootIdx() {
    hSemi(chordRoot) => int rs;
    scales[scaleType] @=> int scl[];
    for(0 => int i; i < scl.cap(); i++) {
        if(scl[i] == rs) { if(rs > 6) return i - scl.cap(); return i; }
    }
    return 0;
}
// Is this MIDI note a tone of the current chord?
fun int isChordTone(int m) {
    for(0 => int i; i < 3; i++) if(fMod(m - key - hSemi(chordRoot + i * 2), 12) == 0) return 1;
    return 0;
}
// A sustained note a semitone or tritone from a chord tone clashes: move it to the nearest chord tone
fun int snapToChord(int m, int avoid) {
    if(isChordTone(m)) return m;
    0 => int clash;
    for(0 => int i; i < 3; i++) {
        fMod(m - key - hSemi(chordRoot + i * 2), 12) => int iv;
        if(iv == 1 || iv == 11 || iv == 6) 1 => clash;
    }
    if(!clash) return m;
    // nearest chord tone, but not the note we just played (that would flatten the line)
    for(1 => int d; d < 6; d++) {
        if(isChordTone(m - d) && m - d != avoid) return m - d;
        if(isChordTone(m + d) && m + d != avoid) return m + d;
    }
    return m;
}
// Fold a MIDI note into [lo, lo+span)
fun int fold(int m, int lo, int span) {
    while(m < lo) m + 12 => m;
    while(m >= lo + span) m - 12 => m;
    return m;
}

// Lead motif: 4-bar phrase (64 steps) — sparse melodica, delay fills the space
-99 => int REST; // rest sentinel (negative degrees are real notes below the root)
64 => int PHRASE_LEN;
int motif[64];
int bassLine[64];
int bassLen[64];    // bass note length in steps (dub bass is rhythm: notes AND gaps)
int delayThrow[64]; // 1 = throw this note into the dub delay
0 => int motifGenerated;
0 => int phraseStep;

// Arrangement mask: 0=minimal, 1=bass+drums, 2=+pad/skank, 3=+melodica
int arrangement[16];
// Mixing-desk mutes (energy >= 2): 0=none, 1=drums out (bass + echoes), 2=bass out (drums + echoes)
int dubMute[16];
[[0,0,0,0, 0,0,0,1, 0,0,0,0, 0,0,0,2],
 [0,0,0,2, 0,0,0,0, 0,0,0,2, 0,0,1,0],
 [0,0,0,0, 0,0,0,2, 0,0,1,1, 0,0,0,2],
 [0,0,0,0, 0,0,0,1, 0,0,0,0, 0,0,1,2]] @=> int muteTpl[][];

fun void setMutes() {
    (seed + phraseRepeat) % muteTpl.cap() => int mt;
    for(0 => int i; i < 16; i++) muteTpl[mt][i] => dubMute[i];
}

fun void setBass(int pos, int deg, int len) { deg => bassLine[pos]; len => bassLen[pos]; }

fun void generateMotif() {
    seed => int s;
    for(0 => int i; i < PHRASE_LEN; i++) {
        REST => motif[i];
        REST => bassLine[i];
        0 => bassLen[i];
        0 => delayThrow[i];
    }
    scales[scaleType].cap() => int sLen;

    // --- CELL ---
    int cellDeg[3];
    int cellPos[3];
    0 => cellDeg[0];
    [1, 2, -1, 2, 1, -2] @=> int leaps[];
    leaps[s % leaps.cap()] => int leap1;
    leap1 => cellDeg[1];
    [-1, 0, 1, -1, 0] @=> int resolves[];
    cellDeg[1] + resolves[(s / 2) % resolves.cap()] => cellDeg[2];
    // Third note must move: no repeated note, no dead "there and back"
    if(cellDeg[2] == cellDeg[1]) { if(leap1 > 0) cellDeg[1] + 1 => cellDeg[2]; else cellDeg[1] - 1 => cellDeg[2]; }
    if(cellDeg[2] == cellDeg[0]) { if(leap1 > 0) cellDeg[1] + 1 => cellDeg[2]; else cellDeg[1] - 1 => cellDeg[2]; }

    // Dub cell rhythm: spacious (0,6,12) family — the delay echoes fill the gaps
    [[0, 6, 12], [0, 6, 10], [2, 8, 14], [0, 8, 14], [0, 4, 10]] @=> int cellRhythms[][];
    cellRhythms[(s / 3) % cellRhythms.cap()] @=> int cR[];
    cR[0] => cellPos[0]; cR[1] => cellPos[1]; cR[2] => cellPos[2];

    s % 3 => int varType;

    // Bar 1: state the cell; throw the last note
    for(0 => int i; i < 3; i++) cellDeg[i] => motif[cellPos[i]];
    1 => delayThrow[cellPos[2]];

    // Bar 2: varied cell (transpose a 3rd / invert / retrograde)
    int v[3];
    if(varType == 0) { for(0 => int i; i < 3; i++) cellDeg[i] + 2 => v[i]; }
    else if(varType == 1) { for(0 => int i; i < 3; i++) cellDeg[0] - (cellDeg[i] - cellDeg[0]) => v[i]; }
    else { for(0 => int i; i < 3; i++) cellDeg[2 - i] => v[i]; }
    for(0 => int i; i < 3; i++) v[i] => motif[16 + cellPos[i]];
    1 => delayThrow[16 + cellPos[1]];

    // Bar 3: the cell twice — higher, then original with an approach note from below
    for(0 => int i; i < 3; i++) cellDeg[i] + 2 => motif[32 + cellPos[i] / 2];
    cellDeg[0] - 1 => motif[32 + 7];
    for(0 => int i; i < 3; i++) cellDeg[i] => motif[40 + cellPos[i] / 2];
    1 => delayThrow[40 + cellPos[2] / 2];

    // Bar 4: half the cell, then resolve to the root and let the echo carry it
    cellDeg[0] => motif[48 + cellPos[0]];
    cellDeg[1] => motif[48 + cellPos[0] + 3];
    0 => motif[56];
    1 => delayThrow[56];

    // --- BASS: the riddim. Cell-derived, repeats every 4 bars like a real dub bassline ---
    // Roles: 0=root, 1=cell[1], 2=cell[2], 3=fifth, 4=octave
    4 => int fifth; if(sLen == 5) 3 => fifth;
    [[0,4, 6,2, 8,3, 12,2, 14,2],
     [2,3, 6,1, 8,4, 12,2, 14,2],
     [0,6, 7,1, 8,4, 12,2, 14,1],
     [0,2, 3,2, 6,2, 8,4, 14,2]] @=> int bRhy[][];   // pairs: step, length
    [[0, 1, 0, 3, 2],
     [0, 1, 0, 3, 2],
     [0, 1, 3, 0, 4],
     [0, 1, 2, 0, 3]] @=> int bRole[][];   // beats 1 and 3 always root or fifth
    (s / 5) % bRhy.cap() => int bt;
    int roleDeg[5];
    0 => roleDeg[0]; cellDeg[1] => roleDeg[1]; cellDeg[2] => roleDeg[2];
    fifth => roleDeg[3]; sLen => roleDeg[4];
    for(0 => int n; n < 5; n++) {
        bRhy[bt][n * 2] => int pos; bRhy[bt][n * 2 + 1] => int len;
        roleDeg[bRole[bt][n]] => int d;
        // Bar 1: as written
        setBass(pos, d, len);
        // Bar 2: same rhythm, follows the lead's variation
        d => int d2;
        if(bRole[bt][n] == 1 || bRole[bt][n] == 2) {
            if(varType == 0) d + 2 => d2;
            else if(varType == 1) 0 - d => d2;
            else roleDeg[3 - bRole[bt][n]] => d2; // retrograde: swap cell[1] and cell[2]
        }
        setBass(16 + pos, d2, len);
        // Bar 3: busier — passing cell tone in the gap after each note
        setBass(32 + pos, d, len);
        if(len >= 3 && pos + 2 < 16) { setBass(32 + pos, d, 2); setBass(32 + pos + 2, cellDeg[1], 1); }
        // Bar 4: just roots and fifths, resolving
        if(bRole[bt][n] == 3) setBass(48 + pos, fifth, len); else setBass(48 + pos, 0, len);
    }

    // --- ARRANGEMENT: dub "version" — melodica comes and goes in whole phrases ---
    s % 4 => int arrType;
    if(arrType == 0) {
        [1,1,2,2, 2,2,2,2, 3,3,3,3, 2,2,1,1] @=> int arrA[];   // build
        for(0 => int i; i < 16; i++) arrA[i] => arrangement[i];
    } else if(arrType == 1) {
        [2,2,3,3, 1,1,2,2, 2,2,3,3, 1,1,2,1] @=> int arrB[];   // call-response
        for(0 => int i; i < 16; i++) arrB[i] => arrangement[i];
    } else if(arrType == 2) {
        [3,3,3,3, 2,2,2,2, 1,1,1,1, 2,2,3,3] @=> int arrC[];   // full then strip
        for(0 => int i; i < 16; i++) arrC[i] => arrangement[i];
    } else {
        [1,1,2,2, 2,2,3,3, 1,1,1,1, 3,3,2,2] @=> int arrD[];   // spacious
        for(0 => int i; i < 16; i++) arrD[i] => arrangement[i];
    }
    setMutes();

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
0.50 => rvFb1.gain; 0.48 => rvFb2.gain; // more feedback — cavernous
0.44 => rvFb3.gain; 0.40 => rvFb4.gain;
0.35 => rvMix.gain; // reverb is louder in the mix
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
    <<< "Beatpilot [dub]: samples loaded" >>>;
} else {
    <<< "Beatpilot [dub]: no samples found, using synthesis" >>>;
}

// ============ DUB DELAY THROW BUS ============
// THE signature dub sound — long feedback delay with filtering
// Certain notes and snare hits get "thrown" into this delay
// Wet is tapped before the feedback gain so echo level and tail length are independent.
Gain delaySend => DelayL dubDly => LPF dlyLP => HPF dlyHP => Gain dlyFb => delaySend;
dlyHP => Gain dlyWet => master;

// Dotted eighth (3 sixteenths = 0.64s at 70 BPM) — the classic tape-echo throw
(stepDur * 6) => dubDly.max;
(stepDur * 3) => dubDly.delay;
0.50 => float DLY_FB_BASE;   // repeats die over ~3s; swells push to 0.70 max (loop stays < 1)
0.38 => float DLY_WET_BASE;  // first echo of a full throw sits ~9 dB under the dry note
DLY_FB_BASE => dlyFb.gain;
1400.0 => dlyLP.freq;   // echoes get darker with each repeat
300.0 => dlyHP.freq;    // and thinner — no mud building under the sub
0.0 => dlyWet.gain;
DLY_WET_BASE => float dlyWetTarget;


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

// One-drop (kick on beat 3, step 8) at energy 1-2; steppers (every beat) at energy 3
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0]] @=> int kPat[][];

// ============ VELOCITY MAPS ============
// Kick: beat 3 is the one-drop — HARD. Everything else ghost-level.
[0.75, 0.0, 0.0, 0.0, 0.6, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.6, 0.0, 0.0, 0.0] @=> float kickVel[];
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
// Spring tank: two short resonant combs + band-pass = the metallic "boing" on every rim
snrG => Gain springIn;
springIn => DelayL sp1 => Gain sp1Fb => sp1;
springIn => DelayL sp2 => Gain sp2Fb => sp2;
0.05::second => sp1.max; 0.0313::second => sp1.delay; 0.80 => sp1Fb.gain;
0.05::second => sp2.max; 0.0467::second => sp2.delay; 0.76 => sp2Fb.gain;
sp1 => BPF springBP => Gain springOut => master;
sp2 => springBP;
1700.0 => springBP.freq; 0.8 => springBP.Q;
0.6 => springIn.gain; 0.55 => springOut.gain;

// Snare on beat 3 — layered with kick for the one-drop
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0]] @=> int snrPat[][];

// ============ SUB BASS ============
// Dub sub bass: THE foundation. Deep sine, heaviest bass in any genre.
// Detuned pair for width + slow drift LFO
// Sine pair = the weight; TriOsc layer = odd harmonics so the line is audible on small speakers.
// ADSR gates every note: dub bass is as much about the gaps as the notes.
SinOsc bassOsc1 => LPF bassF => ADSR bassEnv => Gain bassG => master;
SinOsc bassOsc2 => bassF;
TriOsc bassTri => bassF;
0.6 => bassOsc1.gain; 0.55 => bassOsc2.gain; 0.22 => bassTri.gain;
350.0 => bassF.freq; 1.2 => bassF.Q;
bassEnv.set(6::ms, 120::ms, 0.85, 70::ms);
0.30 => bassG.gain;
350.0 => float bassFiltTarget;
0 => int bassRemain; // steps left on the current bass note
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
600.0 => padF.freq; 1.2 => padF.Q; // dark but above the sub
0.0 => padG.gain;
0.0 => float padGainTarget;
600.0 => float padFiltTarget;
0 => int padLastDeg;
0.0 => float padLfoPhase;

// Pad feeds reverb heavily — dub reverb tails are essential
// pad routes through master to reverb
// reverb send via master bus

// ============ SKANK GUITAR ============
// Short, choppy chord hits on off-beats — the "chick-a chick-a" rhythm
// Filtered noise + TriOsc for percussive, muted guitar approximation
// Skank: sample-based if available, Mandolin fallback
// Synth fallback is a 3-voice chord (root/3rd/5th) — a skank is a chord chop, not a single note
Mandolin skankSynth => ADSR skankChop => LPF skankFilt => Gain skankG => master;
Mandolin skankSynth2 => skankChop;
Mandolin skankSynth3 => skankChop;
skankG => Gain skankToDelay => delaySend;
0.0 => skankToDelay.gain;
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
    <<< "Beatpilot [dub]: guitar skanks loaded" >>>;
}
0.0 => skankG.gain;

// Skank feeds reverb for dub wash
// skank routes through master to reverb
// reverb send via master bus

// Skank on beats 2 and 4 (steps 4, 12) — gated by the arrangement like a desk mute
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0]] @=> int skankPat[][];

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
        newSeed % 256 => seed;
        newSeed % 2 => variant;
        seed % progs.cap() => progIdx;
        -1 => phraseBar; // the advance below lands it on bar 0
        0 => chordIdx;
        0 => phraseRepeat;
        for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
        realChord(progs[progIdx][0]) => chordRoot;
        generateMotif();
        }

        if(newTs != lastEventTs && newTs > 0) {
            newTs => lastEventTs;

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
                0.32 => skankG.gain;
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
    nf.write("genre dub\n");
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
                // Dub: up a 4th (+3 degrees of the 7-note harmony scale), kept a real triad
                realChord(progs[progIdx][subIdx] + 3) => int sub;
                if(sub != realChord(progs[progIdx][subIdx])) sub => chordSub[subIdx];
            }
            if(motifGenerated) setMutes(); // desk mutes move around each time through
        }
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        realChord(progs[progIdx][chordIdx]) => chordRoot;
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
                DLY_WET_BASE => dlyWetTarget;
                DLY_FB_BASE => dlyFb.gain;
            } else {
                introBar $ float / introLen $ float => float p;
                // HPF sweeps down: reveal the sub bass gradually
                1000.0 * (1.0 - p) * (1.0 - p) + 20.0 => fxHPF.freq;
                // Reverb + delay wash: classic dub intro — echoes building
                0.38 => rvMix.gain;
                0.50 => rvFb1.gain; 0.48 => rvFb2.gain;
                DLY_WET_BASE * 1.4 => dlyWetTarget;
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
                    DLY_WET_BASE + p * 0.20 => dlyWetTarget;
                    DLY_FB_BASE + p * 0.20 => dlyFb.gain;
                }
            }
        }
        if(fxType == 0 && !introActive) {
            if(rvMix.gain() > 0.29) rvMix.gain() * 0.95 + 0.28 * 0.05 => rvMix.gain;
            if(rvFb1.gain() > 0.46) rvFb1.gain() * 0.95 + 0.45 * 0.05 => rvFb1.gain;
            if(rvFb2.gain() > 0.43) rvFb2.gain() * 0.95 + 0.42 * 0.05 => rvFb2.gain;
            if(dlyFb.gain() > DLY_FB_BASE + 0.01) dlyFb.gain() * 0.95 + DLY_FB_BASE * 0.05 => dlyFb.gain;
            if(transition != 4 && dlyWetTarget > DLY_WET_BASE + 0.005) dlyWetTarget * 0.9 + DLY_WET_BASE * 0.1 => dlyWetTarget;
        }
    }

    // ---- TRANSITION FX ----
    transitionStep + 1 => transitionStep;

    0 => int kickMuted;
    0 => int hatFill;
    // Mixing-desk mute for this bar (1 = drums out, 2 = bass out)
    0 => int muteNow;
    if(motifGenerated && energy >= 2 && transition == 0 && !introActive && phraseBar >= 0) dubMute[phraseBar] => muteNow;
    if(muteNow == 1) 1 => kickMuted;

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
        DLY_WET_BASE * 1.4 => dlyWetTarget;
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
        if(muteNow != 1 && chPat[energy][s]) {
            if(useSamples) { 0 => smpHat.pos; 0.06 + 0.08 * hatVel[s] => smpHatG.gain; }
            0.02 + 0.05 * hatVel[s] => chG.gain;
            if(useSamples) chG.gain() * 0.3 => chG.gain;
            chEnv.keyOn();
        }
        if(muteNow != 1 && ohPat[energy][s]) {
            if(useSamples) { 0 => smpHatOpen.pos; 0.05 + 0.06 * hatVel[s] => smpHatOpenG.gain; }
            0.02 + 0.03 * hatVel[s] => ohG.gain;
            if(useSamples) ohG.gain() * 0.3 => ohG.gain;
            ohEnv.keyOn();
        }
    }

    // ---- SNARE / RIMSHOT (one-drop on beat 3, with delay throws) ----
    if(muteNow != 1 && snrPat[energy][s]) {
        snrVel[s] => float sVel;
        if(useSamples) { 0 => smpRimshot.pos; sVel * 0.20 => smpRimshotG.gain; }
        sVel * 0.08 => snrG.gain;
        if(useSamples) snrG.gain() * 0.3 => snrG.gain;
        snrEnv.keyOn();
        // Throw the snare into the delay at chord ends and into desk mutes — not every hit
        0 => int nextMute;
        if(motifGenerated && energy >= 2) dubMute[(phraseBar + 1) % 16] => nextMute;
        if(phraseBar % 4 == 3 || nextMute > 0 || muteNow == 2) {
            0.9 => snrToDelay.gain;
        } else {
            0.0 => snrToDelay.gain;
        }
        // Snare feeds reverb
        // snare echo handled by dub delay throw
    }

    // ---- DRUM MICRO-VARIATION ----
    if(energy >= 2 && muteNow != 1) {
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
    if(drumFill > 0 && energy >= 1 && muteNow != 1) {
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

    // ---- SKANK GUITAR (beats 2 & 4, chord chop, comes and goes with the arrangement) ----
    if(transition != 4 && energy >= 2 && arrLevel >= 2 && skankPat[energy][s]) {
        if(useSkankSamples) {
            // Real guitar sample — pick from 4 variations
            (seed + phraseBar) % 4 => int skIdx;
            0 => smpSkank[skIdx].pos;
            0.20 + Math.random2f(0.0, 0.08) => smpSkankG.gain;
        } else {
            // Synth fallback: close-voiced triad around middle C
            48 + key => int skLo; if(key > 5) skLo - 12 => skLo;
            Std.mtof(fold(key + hSemi(chordRoot), skLo + 6, 12)) => skankSynth.freq;
            Std.mtof(fold(key + hSemi(chordRoot + 2), skLo + 6, 12)) => skankSynth2.freq;
            Std.mtof(fold(key + hSemi(chordRoot + 4), skLo + 6, 12)) => skankSynth3.freq;
            0.4 + Math.random2f(0.0, 0.2) => skankSynth.pluckPos;
            0.8 => skankSynth.pluck; 0.7 => skankSynth2.pluck; 0.7 => skankSynth3.pluck;
            skankChop.keyOn();
        }
        // Last skank of each chord goes into the echo
        if(s == 12 && phraseBar % 4 == 3) 0.8 => skankToDelay.gain; else 0.0 => skankToDelay.gain;
    }

    // ---- SUB BASS (the riddim: cell-derived, gated notes, desk mute 2 drops it out) ----
    0 => int bassOn;
    if(transition != 4 && energy >= 1 && arrLevel >= 1 && motifGenerated && muteNow != 2) 1 => bassOn;
    if(bassRemain > 0) {
        bassRemain - 1 => bassRemain;
        if(bassRemain == 0) bassEnv.keyOff();
    }
    if(!bassOn) {
        if(bassRemain > 0) { 0 => bassRemain; bassEnv.keyOff(); }
    } else {
        bassLine[phraseStep % PHRASE_LEN] => int bDeg;
        if(bDeg != REST) {
            rootIdx() => int ri;
            // Tonic sits E1..D#2 (41-78 Hz): heavy but still pitched
            24 + key => int bBase; if(key < 4) bBase + 12 => bBase;
            bBase + mSemi(ri + bDeg) => int bMidi;
            fold(bMidi, 28, 26) => bMidi;
            if(bassLen[phraseStep % PHRASE_LEN] >= 3) snapToChord(bMidi, -1) => bMidi; // long notes sit on the chord
            Std.mtof(bMidi) => float bFreq;
            bFreq => bassOsc1.freq;
            bFreq * 1.002 => bassOsc2.freq; // slight detune for width
            bFreq => bassTri.freq;
            // Bass drift LFO — slow, alive
            bassDriftPhase + 0.0001 => bassDriftPhase;
            bassOsc2.freq() + Math.sin(bassDriftPhase) * 0.3 => bassOsc2.freq;
            bassLen[phraseStep % PHRASE_LEN] => bassRemain;
            if(bassRemain < 1) 1 => bassRemain;
            bassEnv.keyOn();
            // Filter follows phrase: opens in bar 3, accents on the beat
            if(phraseStep >= 32 && phraseStep < 48) 520.0 => bassFiltTarget;
            else if(s % 4 == 0) 420.0 => bassFiltTarget;
            else 340.0 => bassFiltTarget;
        }
    }

    // ---- PAD (dark minor triad, follows arrangement + phrase dynamics) ----
    if(transition != 4 && s == 0 && arrLevel >= 2) {
        // Close voicing between E3 and E4: smooth voice leading, clear of the sub
        Std.mtof(fold(key + hSemi(chordRoot), 52, 12)) => padOsc1.freq;
        Std.mtof(fold(key + hSemi(chordRoot + 2), 52, 12)) => padOsc2.freq;
        Std.mtof(fold(key + hSemi(chordRoot + 4), 52, 12)) => padOsc3.freq;
        // Detune for width
        padOsc1.freq() * 0.998 => padOsc1.freq;
        padOsc3.freq() * 1.002 => padOsc3.freq;
        // Pad dynamics follow phrase position
        phraseBar % 4 => int barInChord;
        if(barInChord < 2) 0.05 => padGainTarget;
        else if(barInChord == 2) 0.09 => padGainTarget;
        else 0.035 => padGainTarget;
        if(energy >= 3) padGainTarget * 1.3 => padGainTarget;
        // Dark filter — opens through the chord
        550.0 + barInChord * 120.0 => padFiltTarget;
    } else if(arrLevel < 2) {
        0.0 => padGainTarget;
    }

    // ---- MELODICA/ORGAN LEAD (cell motif, selective delay throws) ----
    if(transition != 4 && motifGenerated && arrLevel >= 3) {
        motif[phraseStep % PHRASE_LEN] => int deg;
        // Motif variation per repetition
        phraseBar / 4 => int motifRep;
        if(motifRep == 1 && deg != REST && (seed + phraseStep) % 5 == 0) REST => deg;
        if(motifRep == 3 && deg != REST && phraseStep % 8 == 6) deg - 1 => deg;
        if(deg != REST) {
            rootIdx() => int ri;
            // Lead tonic G3..F#4 region: melodica register, above the pad
            60 + key => int lBase; if(key > 7) lBase - 12 => lBase;
            lBase + mSemi(ri + deg) => int lMidi;
            if(motifRep == 2 && phraseStep >= 32 && phraseStep < 48) lMidi + 12 => lMidi;
            if(lMidi > 84) lMidi - 12 => lMidi; // keep it a melodica, not a whistle
            // Sustained notes must not rub against the chord; quick passing/approach notes may
            0 => int passing;
            if(motif[(phraseStep + 1) % PHRASE_LEN] != REST) 1 => passing;
            if(!passing) snapToChord(lMidi, lastLeadDeg) => lMidi;
            lMidi => lastLeadDeg; // (holds the last lead MIDI note)
            Std.mtof(lMidi) => float ldFreq;
            ldFreq => ldSin1.freq;
            ldFreq * 1.003 => ldSin2.freq; // detune pair
            ldFreq => ldTri1.freq;
            ldFreq * 0.997 => ldTri2.freq; // detune pair
            // Slow pitch drift LFO
            ldDriftPhase + 0.0001 => ldDriftPhase;
            ldSin2.freq() + Math.sin(ldDriftPhase) * 0.5 => ldSin2.freq;

            // Velocity: sparse, bar 3 peaks, bar 4 pulls back
            phraseStep % 16 => int localStep;
            0.07 => float ldVel;
            if(localStep % 4 == 0) 0.11 => ldVel;
            else if(localStep % 2 == 0) 0.09 => ldVel;
            if(phraseStep >= 32 && phraseStep < 48) ldVel * 1.15 => ldVel;
            if(phraseStep >= 48) ldVel * 0.6 => ldVel;
            1300.0 + Math.random2f(0.0, 500.0) => ldFiltTarget;
            ldVel => ldAmpTarget;

            // DELAY THROW: a light send on every note, a full throw on the marked ones
            // (the send decays per substep, so only the attack is thrown)
            0.12 => ldToDelay.gain;
            if(delayThrow[phraseStep % PHRASE_LEN]) 0.9 => ldToDelay.gain;
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
            44.0 + 56.0 * Math.exp(-kickPh * 6.0) => kickOsc.freq;
            kickOsc.freq() * 3.0 => kickLPF.freq;
            kickOsc.gain() * 0.93 => kickOsc.gain; // round but short enough to leave the bass its own room
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
        if(bassFiltTarget > 300.0) bassFiltTarget * 0.996 => bassFiltTarget;

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
        if(padFiltTarget > 550.0) padFiltTarget * 0.9998 => padFiltTarget;
        padG.gain() + (padGainTarget - padG.gain()) * 0.008 => padG.gain;
        if(transition == 4) 0.0 => padGainTarget;

        // Delay wet level smooth — important for dub dynamics
        dlyWet.gain() + (dlyWetTarget - dlyWet.gain()) * 0.02 => dlyWet.gain;

        // Snare delay send decay — don't leave it open
        if(snrToDelay.gain() > 0.01) snrToDelay.gain() * 0.9 => snrToDelay.gain;
        if(skankToDelay.gain() > 0.01) skankToDelay.gain() * 0.85 => skankToDelay.gain;
        if(ldToDelay.gain() > 0.13) ldToDelay.gain() * 0.93 => ldToDelay.gain;

        // FX: smooth HPF back toward 20Hz when not active (skip during intro + HPF sweep)
        if(fxType != 1 && !introActive) fxHPF.freq() + (20.0 - fxHPF.freq()) * 0.04 => fxHPF.freq;

        // Master gain smooth
        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain * volume => master.gain;

        thisStepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
