// ambient.ck - Beatpilot Ambient Engine
// No drums. Evolving pads, warm drones, shimmering textures, all in space.

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
me.dir() + "/../samples/ambient/" => string smpDir;
0 => int useSamples;

// ============ CLOCK ============
70.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;
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
0 => int phraseStep;

// ============ FX STATE (occasional tension/release) ============
0 => int fxType;  // 0=none, 1=hpf_sweep, 2=reverb_wash, 3=shimmer_swell
0 => int fxBar;
0 => int fxLen;

// ============ INTRO STATE (call to the dancefloor) ============
0 => int introActive;
0 => int introBar;
0 => int introLen;

// ============ ARP LINE (64 steps = 4 bars of 16 steps) ============
int arpLine[64];

// ============ ARRANGEMENT MASK (16 bars) ============
// 0=drone only, 1=drone+sub, 2=+pad, 3=+shimmer+arp
int arrangement[16];

// ============ PHRASE / CHORD PROGRESSION ============
// Mix of warm and dark progressions
// 0-1: warm/open, 2-3: minor/cinematic, 4-5: dark/tense
[[0, 3, 4, 2],   // warm: I-IV-V-III
 [0, 4, 3, 1],   // warm: I-V-IV-II
 [0, 3, 5, 2],   // minor: i-iv-vi-iii (melancholy)
 [0, 4, 1, 3],   // dark: i-v-bII-iv (Zimmer tension)
 [0, 5, 3, 1],   // ominous: i-bVI-iv-bII (descending dread)
 [0, 3, 4, 5]]   // building: i-iv-v-bVI (unresolved)
    @=> int progs[][];
0 => int progIdx;
0 => int chordIdx;
0 => int chordRoot;
0 => int phraseBar;
0 => int phraseRepeat;
int chordSub[4];
0 => int mood;  // 0=warm, 1=dark — affects scale choice and tension

// ============ AUTO-EVOLUTION ============
// 0=normal, 1=thin, 2=swell, 3=shimmer, 4=full, 5=tension, 6=release
0 => int autoSection;
0 => int autoSectionBar;
0 => int autoActive;
[0, 10, 8, 6, 2, 8, 4] @=> int autoSectionLen[];
// Cycle: normal → thin → swell → tension → shimmer → release → normal
[1, 2, 5, 6, 0, 3, 4] @=> int autoNextSection[];

// ============ MASTER BUS + REVERB ============
Gain masterOut => HPF fxHPF => dac;
20.0 => fxHPF.freq; 0.5 => fxHPF.Q;
Gain master => Gain dryOut => masterOut;
0.0 => master.gain;

// Multi-tap delay reverb — 4 taps with feedback for diffuse wash
master => DelayL rv1 => Gain rvFb1 => LPF rvF1 => Gain rvMix => masterOut;
master => DelayL rv2 => Gain rvFb2 => LPF rvF2 => rvMix;
master => DelayL rv3 => Gain rvFb3 => LPF rvF3 => rvMix;
master => DelayL rv4 => Gain rvFb4 => LPF rvF4 => rvMix;
// Cross-feed for density
rvFb1 => rv3; rvFb2 => rv4; rvFb3 => rv1; rvFb4 => rv2;
// Tap times: prime-ish ratios to avoid metallic resonance
0.15::second => rv1.max; 0.1347::second => rv1.delay;
0.2::second => rv2.max; 0.1781::second => rv2.delay;
0.25::second => rv3.max; 0.2311::second => rv3.delay;
0.35::second => rv4.max; 0.3109::second => rv4.delay;
// Feedback + darkening
0.45 => rvFb1.gain; 0.43 => rvFb2.gain; 0.41 => rvFb3.gain; 0.40 => rvFb4.gain;
2200.0 => rvF1.freq; 2000.0 => rvF2.freq; 1800.0 => rvF3.freq; 1600.0 => rvF4.freq;
0.25 => rvMix.gain; // reverb wet level
0.75 => dryOut.gain; // dry level

// ============ SAMPLE BUFFERS (textural percussion) ============
SndBuf smpTriangle => Gain smpTriangleG => master;
SndBuf smpBelltree => Gain smpBelltreeG => master;
SndBuf smpSizzle => Gain smpSizzleG => master;
SndBuf smpShaker => Gain smpShakerG => master;
0.0 => smpTriangleG.gain; 0.0 => smpBelltreeG.gain;
0.0 => smpSizzleG.gain; 0.0 => smpShakerG.gain;

FileIO smpTest;
if(smpTest.open(smpDir + "triangle.wav", FileIO.READ)) {
    smpTest.close();
    smpTriangle.read(smpDir + "triangle.wav");
    smpBelltree.read(smpDir + "belltree.wav");
    smpSizzle.read(smpDir + "sizzle.wav");
    smpShaker.read(smpDir + "shaker.wav");
    smpTriangle.samples() => smpTriangle.pos;
    smpBelltree.samples() => smpBelltree.pos;
    smpSizzle.samples() => smpSizzle.pos;
    smpShaker.samples() => smpShaker.pos;
    1 => useSamples;
    <<< "Beatpilot [ambient]: samples loaded" >>>;
} else {
    <<< "Beatpilot [ambient]: no samples found, using synthesis" >>>;
}

// ============ SCALES ============
// 0: pentatonic major (safe, bright)
// 1: minor pentatonic (mellow)
// 2: harmonic minor (dark, cinematic — that raised 7th)
// 3: phrygian (ominous — half-step root, Zimmer territory)
// 4: minor (natural)
// 5: whole-half diminished (maximum tension)
[[0,2,4,7,9], [0,3,5,7,10], [0,2,3,5,7,8,11], [0,1,3,5,7,8,10], [0,2,3,5,7,8,10], [0,1,3,4,6,7,9,10], [0,2,4,5,7,9,11]] @=> int scales[][];
// 6: major (warm, real triads)

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    scl.cap() => int n;
    degree / n => int oct;
    degree % n => int d;
    if(d < 0) { d + n => d; oct - 1 => oct; }
    return key + octave * 12 + scl[d] + oct * 12;
}

// Voice-led triad: move each voice to the nearest tone of the new chord
// (all 3 chord tones covered), kept inside lo..hi. Writes MIDI into v[].
fun void voiceLead(int v[], int root, int lo, int hi) {
    int t[3];
    for(0 => int i; i < 3; i++) note(root + 2 * i, 0) % 12 => t[i];
    [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]] @=> int perms[][];
    999999 => int best; int bv[3];
    for(0 => int p; p < 6; p++) {
        0 => int cost; int cv[3];
        for(0 => int i; i < 3; i++) {
            t[perms[p][i]] => int pc;
            // nearest pitch with this pitch class to the old voice
            v[i] - ((v[i] - pc) % 12 + 12) % 12 => int c;
            if(v[i] - c > 6) c + 12 => c;
            while(c < lo) c + 12 => c;
            while(c > hi) c - 12 => c;
            c => cv[i];
            Math.abs(c - v[i]) +=> cost;
        }
        // avoid unisons between voices
        if(cv[0] == cv[1] || cv[1] == cv[2] || cv[0] == cv[2]) 100 +=> cost;
        if(cost < best) { cost => best; for(0 => int i; i < 3; i++) cv[i] => bv[i]; }
    }
    for(0 => int i; i < 3; i++) bv[i] => v[i];
}

// ============ DRONE (layered: FM + warm TriOsc) ============
// FM layer — glassy overtones
SinOsc droneMod => SinOsc droneCarr => LPF droneFilt => Gain droneG => master;
2 => droneCarr.sync;
0.25 => droneCarr.gain;
20.0 => droneMod.gain;
300.0 => droneFilt.freq; 0.5 => droneFilt.Q;
0.0 => droneG.gain;
// Warm layer — detuned triangle pair
TriOsc droneWarm1 => LPF droneWF => droneG;
TriOsc droneWarm2 => droneWF;
0.15 => droneWarm1.gain; 0.15 => droneWarm2.gain;
400.0 => droneWF.freq; 0.6 => droneWF.Q;
0.0 => float droneAmpTarget;
0.0 => float droneAmpCurrent;
20.0 => float droneModTarget;

// ============ SUB DRONE ============
TriOsc subDrone => LPF subFilt => Gain subG => master;
200.0 => subFilt.freq; 1.0 => subFilt.Q;
0.0 => subG.gain;
0.0 => float subAmpTarget;
0.0 => float subAmpCurrent;

// ============ PAD (detuned tri pairs x3 = 6 oscillators for warmth) ============
TriOsc pad1a => LPF padFilt => Gain padG => master;
TriOsc pad1b => padFilt;
TriOsc pad2a => padFilt;
TriOsc pad2b => padFilt;
TriOsc pad3a => padFilt;
TriOsc pad3b => padFilt;
0.15 => pad1a.gain; 0.15 => pad1b.gain;
0.15 => pad2a.gain; 0.15 => pad2b.gain;
0.12 => pad3a.gain; 0.12 => pad3b.gain;
1200.0 => padFilt.freq; 0.7 => padFilt.Q;
0.0 => padG.gain;
0.0 => float padAmpTarget;
0.0 => float padAmpCurrent;
1200.0 => float padFiltTarget;
0.0 => float padLfoPhase;
0.0 => float padBreathPhase;
[55, 59, 62] @=> int padV[];  // voice-led pad voices (MIDI), moved by voiceLead()
float padF[3]; float padT[3];  // current / target base freq per pad voice
float shimF[3]; float shimT[3];
-99 => int voicedRoot;         // chordRoot the pad + shimmer are currently voiced for
0.0 => float droneT; 0.0 => float subT; // drone/sub glide targets (Hz)
0 => int arrLvl;               // effective arrangement level (mask + energy)

// ============ SHIMMER (chord cluster, not single tone) ============
SinOsc shim1 => LPF shimFilt => Gain shimG => master;
SinOsc shim2 => shimFilt;
SinOsc shim3 => shimFilt;
0.2 => shim1.gain; 0.15 => shim2.gain; 0.12 => shim3.gain;
3000.0 => shimFilt.freq; 0.5 => shimFilt.Q;
0.0 => shimG.gain;
0.0 => float shimAmpTarget;
0.0 => float shimAmpCurrent;

// ============ STRINGS (sparse, cinematic — Zimmer-style long tones) ============
// Detuned TriOsc pairs for warmth, very slow attack, played rarely
TriOsc str1a => LPF strFilt => Gain strG => master;
TriOsc str1b => strFilt;
TriOsc str2a => strFilt;
TriOsc str2b => strFilt;
0.15 => str1a.gain; 0.14 => str1b.gain;
0.12 => str2a.gain; 0.11 => str2b.gain;
1800.0 => strFilt.freq; 0.6 => strFilt.Q;
0.0 => strG.gain;
0.0 => float strAmpTarget;
0.0 => float strAmpCurrent;
0.0 => float strFiltTarget;
1800.0 => strFiltTarget;
0.0 => float strF1; 0.0 => float strF2; 0.0 => float strT1; 0.0 => float strT2;

// ============ ARPEGGIO (sparse plucks with longer delay wash) ============
// Two round-robin voices (detuned sine pairs) so a ringing note is never
// re-pitched mid-sound; soft attack, ~3s bell decay, dotted-quarter echoes.
Gain arpBus => LPF arpFilt => Gain arpG => master;
SinOsc arpA[2]; SinOsc arpB[2]; Gain arpEnvG[2];
float arpEnv[2]; float arpPeak[2]; int arpAtk[2];
for(0 => int i; i < 2; i++) {
    arpA[i] => arpEnvG[i]; arpB[i] => arpEnvG[i]; arpEnvG[i] => arpBus;
    0.5 => arpA[i].gain; 0.5 => arpB[i].gain; 0.0 => arpEnvG[i].gain;
}
0 => int arpVoice;
2400.0 => arpFilt.freq; 0.6 => arpFilt.Q;
0.0 => arpG.gain;
// Lead delay: dotted quarter, darkened feedback
arpG => DelayL leadDly => LPF leadLP => Gain leadFb => leadDly;
leadLP => Gain leadOut => master;
(60.0 / BPM * 0.75)::second => leadDly.max => leadDly.delay;
1800.0 => leadLP.freq; 0.45 => leadFb.gain; 0.55 => leadOut.gain;
0.0 => float arpAmpTarget;
0.0 => float arpAmpCurrent;
5 => int melOct;   // melody octave, chosen per chord to keep it in ~C4-C6
-99 => int lastStrNote;
-99 => int lastMelNote;

// ============ TEXTURE (filtered noise breath) ============
Noise texN => BPF texBP => Gain texG => master;
800.0 => texBP.freq; 3.0 => texBP.Q;
0.0 => texG.gain;
0.0 => float texAmpTarget;
0.0 => float texAmpCurrent;

// ============ TENSION RUMBLE (low noise + sine throb) ============
Noise rumbleN => LPF rumbleFilt => Gain rumbleG => master;
SinOsc rumbleSin => rumbleG;
60.0 => rumbleFilt.freq; 2.5 => rumbleFilt.Q;
0.2 => rumbleN.gain;
0.3 => rumbleSin.gain;
30.0 => rumbleSin.freq;
0.0 => rumbleG.gain;
0.0 => float rumbleAmpTarget;
0.0 => float rumbleAmpCurrent;

// ============ GENERATE ARRANGEMENT ============
// Three types based on seed: 0=gradual build, 1=wave, 2=sparse
fun void generateArrangement() {
    seed % 3 => int arrType;
    if(arrType == 0) {
        // Gradual build: drone only -> full, then reset
        [0, 0, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 2, 2, 1, 1] @=> int gb[];
        for(0 => int i; i < 16; i++) gb[i] => arrangement[i];
    } else if(arrType == 1) {
        // Wave: builds, strips, builds again
        [1, 1, 2, 2, 3, 3, 3, 3, 1, 1, 2, 2, 3, 3, 3, 3] @=> int wv[];
        for(0 => int i; i < 16; i++) wv[i] => arrangement[i];
    } else {
        // Sparse: mostly minimal with occasional full moments
        [0, 0, 1, 1, 2, 2, 2, 2, 0, 1, 1, 2, 3, 3, 3, 3] @=> int sp[];
        for(0 => int i; i < 16; i++) sp[i] => arrangement[i];
    }
}

// ============ GENERATE ARP LINE ============
// Places chord tones at musical positions across 64 steps (4 bars x 16 steps)
// Sparse: 2-3 notes per bar, consonant with each chord
fun void generateArp() {
    // Cell-based 4-bar phrase, stored as scale degrees RELATIVE to chordRoot
    // (-99 = rest) so it follows the harmony. Wide ambient spacing.
    for(0 => int i; i < 64; i++) -99 => arpLine[i];
    [0, 2, 4, 2] @=> int startPool[];
    [1, 2, -1, 2, 1, -2] @=> int leapPool[];
    [-1, 0, 1, -1, 0] @=> int resPool[];
    [[0, 6, 10], [0, 4, 10], [2, 8, 12], [0, 8, 12]] @=> int rhy[][];
    startPool[seed % 4] => int c0;
    leapPool[(seed / 4) % 6] => int leap1;
    resPool[(seed / 24) % 5] => int resolve;
    c0 + leap1 => int c1;
    c1 + resolve => int c2;
    rhy[(seed / 3) % 4] @=> int r[];
    (seed / 7) % 3 => int varType;
    // Bar 1: statement
    c0 => arpLine[r[0]]; c1 => arpLine[r[1]]; c2 => arpLine[r[2]];
    // Bar 2: variation (up a 3rd / inverted / retrograde)
    if(varType == 0) {
        c0 + 2 => arpLine[16 + r[0]]; c1 + 2 => arpLine[16 + r[1]]; c2 + 2 => arpLine[16 + r[2]];
    } else if(varType == 1) {
        c0 => arpLine[16 + r[0]]; c0 - leap1 => arpLine[16 + r[1]]; c0 - leap1 - resolve => arpLine[16 + r[2]];
    } else {
        c2 => arpLine[16 + r[0]]; c1 => arpLine[16 + r[1]]; c0 => arpLine[16 + r[2]];
    }
    // Bar 3: cell higher, then an approach note from below into bar 4
    c0 + 2 => arpLine[32 + r[0]]; c1 + 2 => arpLine[32 + r[1]]; c2 + 2 => arpLine[32 + r[2]];
    c0 - 1 => arpLine[32 + 14];
    // Bar 4: half the cell, resolve to the chord root
    c0 => arpLine[48]; c1 => arpLine[48 + r[1]]; 0 => arpLine[48 + 12];
}

// Effective arrangement level: the mask, shaped by energy
// (energy 1 = no melody, energy 3 = one layer richer, energy 0 = drone + sub)
fun int effLevel(int bar) {
    if(bar < 0 || bar > 15) return 0;
    arrangement[bar] => int lv;
    if(energy >= 3) lv + 1 => lv;
    if(energy == 1 && lv > 2) 2 => lv;
    if(energy == 0 && lv > 1) 1 => lv;
    if(lv > 3) 3 => lv;
    return lv;
}

// 1 if a melody pitch is a non-chord tone a semitone from a chord tone
// (a b9 against the sustained pad rings for seconds with sine bells)
fun int clashes(int midi) {
    for(0 => int i; i < 3; i++) {
        note(chordRoot + 2 * i, 0) % 12 => int pc;
        ((midi - pc) % 12 + 12) % 12 => int d;
        if(d == 0) return 0;
    }
    for(0 => int i; i < 3; i++) {
        note(chordRoot + 2 * i, 0) % 12 => int pc;
        ((midi - pc) % 12 + 12) % 12 => int d;
        if(d == 1 || d == 11) return 1;
    }
    return 0;
}

// Re-voice pad + shimmer for the current chord (voice-led), drone/sub targets
fun void voiceChord() {
    if(chordRoot == voicedRoot) return;
    chordRoot => voicedRoot;
    voiceLead(padV, chordRoot, 50, 70);
    for(0 => int i; i < 3; i++) {
        Std.mtof(padV[i]) => padT[i];
        Std.mtof(padV[i] + 12) => shimT[i];
        if(padF[i] < 1.0) { padT[i] => padF[i]; shimT[i] => shimF[i]; }
    }
    Std.mtof(note(chordRoot, 3)) => droneT;
    Std.mtof(note(chordRoot, 2)) => subT;
    if(droneCarr.freq() < 21.0 || masterGain < 0.001) {
        droneT => droneCarr.freq; subT => subDrone.freq;
    }
    if(note(chordRoot, 5) > 72) 4 => melOct; else 5 => melOct;
    // Sustaining strings follow the pad's voice-leading instead of hanging over
    if(strAmpCurrent > 0.001) { Std.mtof(padV[1]) => strT1; Std.mtof(padV[2]) => strT2; }
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
        newScale % 4 => scaleType;
        newSeed % 256 => seed;
        seed % progs.cap() => progIdx;
        // Dark progressions (idx 2-5) use dark scales
        // (seed / 6) decouples the scale from progIdx (= seed % 6).
        // Diminished (5) is left out: all-diminished triads for minutes is noise, not dread.
        if(progIdx >= 2) {
            1 => mood;
            [2, 3, 4] @=> int dark[];
            dark[(seed / 6) % 3] => scaleType; // harmonic minor, phrygian, natural minor
        } else {
            0 => mood;
            [0, 1, 6] @=> int warm[];
            warm[(seed / 6) % 3] => scaleType; // pentatonic major/minor, major
        }
        -1 => phraseBar; // the advance below lands it on bar 0
        0 => chordIdx;
        0 => phraseStep;
        0 => phraseRepeat;
        for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
        progs[progIdx][0] => chordRoot;

        // Generate arp pattern and arrangement from seed
        generateArp();
        generateArrangement();
        -99 => voicedRoot; // new key/scale: re-voice even if the root degree is unchanged
        voiceChord();
        }

        if(newTs != lastEventTs && newTs > 0) {
            newTs => lastEventTs;

            newEnergy => energy;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;

            // Coming back from silence? Ethereal ambient intro
            if(masterTarget < 0.01 && newEnergy >= 2) {
                if((seed + newSeed) % 2 == 0) {
                    1 => introActive;
                    0 => introBar;
                    4 => introLen; // ambient always gets 4-bar intro
                    400.0 => fxHPF.freq;
                }
            }

            1.0 => masterTarget;

            // Cancel auto-evolution
            if(autoActive) {
                0 => autoActive;
                0 => autoSection;
                0 => autoSectionBar;
            }

            // Drone always on — pitch glides to the chord root (substep loop)
            0.06 => droneAmpTarget;
            voiceChord();

            // Arrangement mask gates initial layer targets
            effLevel(phraseBar) => int initArr;
            if(phraseBar < 0) effLevel(0) => initArr;
            if(initArr >= 1) 0.05 => subAmpTarget;
            else 0.0 => subAmpTarget;
            if(initArr >= 2) {
                0.04 => padAmpTarget;
                0.006 => texAmpTarget;
            } else {
                0.0 => padAmpTarget;
                0.0 => texAmpTarget;
            }
            if(initArr >= 3) {
                0.03 => shimAmpTarget;
                0.03 => arpAmpTarget;
            } else {
                0.0 => shimAmpTarget;
                0.0 => arpAmpTarget;
            }
        }
    }
}

// ============ MAIN LOOP ============
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
    nf.write("genre ambient\n");
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

    if(s == 0) {
        readState();
        FileIO vf;
        if(vf.open(volumePath, FileIO.READ)) {
            Std.atoi(vf.readLine()) => int vol;
            vf.close();
            if(vol >= 0 && vol <= 100) vol / 100.0 => volume;
        }
        barsSinceEvent + 1 => barsSinceEvent;

        // Advance chord progression: change every 4 bars
        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) {
            0 => phraseBar;
            phraseRepeat + 1 => phraseRepeat;
            for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
            if(phraseRepeat % 3 == 2 && energy >= 2) {
                (seed * 13 + phraseRepeat) % 4 => int subIdx;
                // Deceptive resolution: up 5 degrees
                // (+5 in a 7-note scale; +3 in pentatonic — +5 there is just the octave)
                scales[scaleType].cap() => int sn;
                (progs[progIdx][subIdx] + sn - 2) % sn => chordSub[subIdx];
            }
        }
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        progs[progIdx][chordIdx] => chordRoot;
        if(chordSub[chordIdx] >= 0) chordSub[chordIdx] => chordRoot;

        // ---- ARRANGEMENT GATING: control which layers are active ----
        effLevel(phraseBar) => arrLvl;
        arrLvl => int arrLevel;
        voiceChord();
        // Drone is always on
        // Sub: arrangement >= 1
        if(arrLevel >= 1) {
            0.05 => subAmpTarget;
        } else {
            0.0 => subAmpTarget;
        }
        // Pad: arrangement >= 2, with dynamics following phrase position
        if(arrLevel >= 2) {
            phraseBar % 4 => int chordBar;
            if(chordBar < 2) 0.04 => padAmpTarget;      // bars 1-2: gentle swell
            else if(chordBar == 2) 0.07 => padAmpTarget; // bar 3: peak
            else 0.03 => padAmpTarget;                     // bar 4: pull back
            if(energy >= 3) padAmpTarget * 1.3 => padAmpTarget;
            0.006 => texAmpTarget;
        } else {
            0.0 => padAmpTarget;
            0.0 => texAmpTarget;
        }
        // Shimmer + arp: arrangement >= 3
        if(arrLevel >= 3) {
            0.03 => shimAmpTarget;
            0.03 => arpAmpTarget;
        } else {
            0.0 => shimAmpTarget;
            0.0 => arpAmpTarget; // layer gate fades; ringing notes + echoes tail off
        }

        // Energy decay
        if(barsSinceEvent > 10 && energy > 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
        }

        // Fade out when idle — no auto-evolution, just graceful silence
        if(barsSinceEvent > 12 && energy == 0) {
            0.0 => masterTarget;
        }

        // ---- INTRO: ethereal fade-in ----
        if(introActive) {
            introBar + 1 => introBar;
            if(introBar > introLen) {
                // Resolve — full sound opens
                0 => introActive;
                20.0 => fxHPF.freq;
                0.25 => rvMix.gain;
                0.45 => rvFb1.gain; 0.43 => rvFb2.gain;
            } else {
                introBar $ float / introLen $ float => float p;
                // HPF sweeps down: gentle, ethereal
                400.0 * (1.0 - p) * (1.0 - p) + 20.0 => fxHPF.freq;
                // Reverb wash: lush, enveloping
                0.38 => rvMix.gain;
                0.50 => rvFb1.gain; 0.48 => rvFb2.gain;
                // Shimmer swell during intro
                0.05 + p * 0.02 => shimAmpTarget;
            }
        }

        // ---- FX: occasional tension/release ----
        if(fxType == 0 && energy >= 2 && phraseBar == 12 && !introActive) {
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
                    // HPF sweep: very subtle for ambient — just thin the low end slightly
                    20.0 + p * p * 400.0 => fxHPF.freq;
                } else if(fxType == 2) {
                    // Reverb wash: lush swell
                    0.25 + p * 0.20 => rvMix.gain;
                    0.45 + p * 0.10 => rvFb1.gain;
                    0.43 + p * 0.10 => rvFb2.gain;
                } else if(fxType == 3) {
                    // Shimmer swell: boost shimmer layer
                    0.03 + p * 0.04 => shimAmpTarget;
                }
            }
        }
        if(fxType == 0 && !introActive) {
            if(rvMix.gain() > 0.26) rvMix.gain() * 0.95 + 0.25 * 0.05 => rvMix.gain;
            if(rvFb1.gain() > 0.46) rvFb1.gain() * 0.95 + 0.45 * 0.05 => rvFb1.gain;
            if(rvFb2.gain() > 0.44) rvFb2.gain() * 0.95 + 0.43 * 0.05 => rvFb2.gain;
        }
    }

    // ---- DRONE / PAD / SHIMMER pitches: voiced at the bar (voiceChord), glide in substeps ----

    // ---- MELODY: cell phrase (relative to chordRoot), round-robin bell voices ----
    phraseBar / 4 => int motifRep;
    arpLine[phraseStep] => int rel;
    // Rep 4 ornament: approach note (step below) into each bar-downbeat note
    if(rel == -99 && motifRep == 3 && phraseStep % 16 == 14 && arpLine[(phraseStep + 2) % 64] > -99)
        arpLine[(phraseStep + 2) % 64] - 1 => rel;
    if(rel > -99 && arrLvl >= 3) {
        phraseStep / 16 => int mBar;
        1 => int play;
        if(motifRep == 1 && (seed + phraseStep) % 5 == 0 && phraseStep != 60) 0 => play; // drop a note
        if(play) {
            melOct => int oct;
            // Non-chord tone a semitone off the harmony: step to a neighbour degree
            if(clashes(note(chordRoot + rel, oct))) {
                note(chordRoot + rel - 1, oct) => int dn;
                if(!clashes(dn) && dn != lastMelNote) rel - 1 => rel;
                else if(!clashes(note(chordRoot + rel + 1, oct))) rel + 1 => rel;
                else rel - 1 => rel;
            }
            note(chordRoot + rel, oct) => int mn;
            if(motifRep == 2 && mBar == 2 && mn + 12 <= 86) mn + 12 => mn; // octave lift on the peak
            mn => lastMelNote;
            Std.mtof(mn) => float f;
            arpVoice => int v;
            1 - arpVoice => arpVoice;
            f * 0.998 => arpA[v].freq; f * 1.002 => arpB[v].freq;
            // contour: bar 3 peaks, bar 4 pulls back; ±5% humanize
            [0.8, 0.85, 1.0, 0.7] @=> float cont[];
            cont[mBar] + ((seed * 17 + stepCount) % 100 - 50) / 1000.0 => arpPeak[v];
            1 => arpAtk[v];
            // Strings: shadow a chord-tone melody note with a bowed 3rd-dyad,
            // once in bars 1 and 3 of the phrase
            scales[scaleType].cap() => int sn;
            ((rel % sn) + sn) % sn => int rd;
            if((rd == 0 || rd == 2 || rd == 4) && (mBar == 0 || mBar == 2) && phraseBar != lastStrNote) {
                phraseBar => lastStrNote; // one bowed dyad per bar
                Std.mtof(note(chordRoot + rel, oct - 1)) => float f1;
                2 => int up; if(rd == 4) sn - 4 => up; // 5th -> root above, never the 7th
                Std.mtof(note(chordRoot + rel + up, oct - 1)) => float f2;
                f1 => strT1; f2 => strT2;
                if(str1a.freq() < 21.0 || strAmpCurrent < 0.001) { f1 => strF1; f2 => strF2; }
                0.022 => strAmpTarget;
                2200.0 + Math.random2f(0.0, 600.0) => strFiltTarget;
            }
        }
    }
    if(arrLvl < 3) 0.0 => strAmpTarget;

    // ---- TEXTURE: noise breath, gated by arrangement ----
    if(arrLvl >= 2 && s == 0 && Math.random2(0, 3) == 0) {
        300.0 + Math.random2f(0.0, 600.0) => texBP.freq;
        0.008 => texAmpTarget;
    }

    // ---- SAMPLE TEXTURES: occasional percussion accents ----
    if(useSamples && arrLvl >= 2 && s == 0) {
        (seed + phraseBar * 11) % 12 => int texRoll;
        if(texRoll == 0 && phraseBar % 4 == 0) {
            // Triangle hit on chord changes
            0 => smpTriangle.pos; 0.04 => smpTriangleG.gain;
        } else if(texRoll == 1 && phraseBar == 8) {
            // Belltree at midpoint of phrase
            0 => smpBelltree.pos; 0.03 => smpBelltreeG.gain;
        } else if(texRoll == 2 && phraseBar % 8 == 7) {
            // Sizzle cymbal at phrase boundaries
            0 => smpSizzle.pos; 0.025 => smpSizzleG.gain;
        } else if(texRoll >= 3 && texRoll <= 4 && phraseBar % 2 == 0 && arrLvl >= 3) {
            // Gentle shaker on every other bar when full arrangement
            0 => smpShaker.pos; 0.02 => smpShakerG.gain;
        }
    }

    // ---- Advance phraseStep (wraps at 64) ----
    (phraseStep + 1) % 64 => phraseStep;

    // ---- SUBSTEP UPDATES ----
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        // Drone envelope + FM drift (darker in tension)
        droneAmpCurrent + (droneAmpTarget - droneAmpCurrent) * 0.003 => droneAmpCurrent;
        droneAmpCurrent => droneG.gain;
        if(mood == 1) {
            // Dark mood: wider FM modulation, more dissonant harmonics
            25.0 + 50.0 * Math.sin(stepCount * 0.0004) => droneModTarget;
            150.0 + 80.0 * Math.sin(stepCount * 0.00015) => droneFilt.freq;
            200.0 + 100.0 * Math.sin(stepCount * 0.0002) => droneWF.freq;
        } else {
            15.0 + 25.0 * Math.sin(stepCount * 0.0003) => droneModTarget;
            220.0 + 100.0 * Math.sin(stepCount * 0.0002) => droneFilt.freq;
            300.0 + 150.0 * Math.sin(stepCount * 0.00025) => droneWF.freq;
        }
        droneMod.gain() + (droneModTarget - droneMod.gain()) * 0.002 => droneMod.gain;
        // Pitch glide to the chord root (~2s), detuned pair with slow drift
        if(droneT > 0.0) {
            droneCarr.freq() + (droneT - droneCarr.freq()) * 0.06 => droneCarr.freq;
            subDrone.freq() + (subT - subDrone.freq()) * 0.06 => subDrone.freq;
        }
        droneCarr.freq() * 1.5 => droneMod.freq;
        droneCarr.freq() * 0.998 => droneWarm1.freq;
        droneCarr.freq() * (1.002 + 0.0006 * Math.sin(stepCount * 0.0011)) => droneWarm2.freq;

        // Sub drone
        subAmpCurrent + (subAmpTarget - subAmpCurrent) * 0.003 => subAmpCurrent;
        subAmpCurrent => subG.gain;

        // Pad: breathing amplitude + filter LFO
        padBreathPhase + 0.0008 => padBreathPhase;
        0.0012 => float padLfoRate;
        if(arrLvl >= 3) padLfoRate * 1.4 => padLfoRate;
        if(phraseBar % 4 == 2) padLfoRate * 1.2 => padLfoRate;
        if(phraseBar >= 12) padLfoRate * 0.8 => padLfoRate;
        padLfoPhase + padLfoRate => padLfoPhase;
        // Amplitude breathes slowly
        padAmpTarget * (0.85 + 0.15 * Math.sin(padBreathPhase)) => float padBreathGain;
        padAmpCurrent + (padBreathGain - padAmpCurrent) * 0.005 => padAmpCurrent;
        padAmpCurrent => padG.gain;
        // Note: padAmpTarget is set per-bar by arrangement gating with phrase dynamics
        // Filter sweeps slowly
        Math.sin(padLfoPhase) * 300.0 => float padLfoMod;
        padFilt.freq() + ((padFiltTarget + padLfoMod) - padFilt.freq()) * 0.008 => padFilt.freq;
        if(padFiltTarget > 500.0) padFiltTarget * 0.99998 => padFiltTarget;

        // Pad: voices glide (~1s) to the voice-led targets; detuned pairs with
        // slow drift on the b side (computed from the base, never cumulative)
        0.0 => float drift;
        for(0 => int i; i < 3; i++) {
            padF[i] + (padT[i] - padF[i]) * 0.08 => padF[i];
            shimF[i] + (shimT[i] - shimF[i]) * 0.08 => shimF[i];
        }
        0.0015 * Math.sin(stepCount * 0.0011) => drift;
        padF[0] * 0.997 => pad1a.freq; padF[0] * (1.003 + drift) => pad1b.freq;
        padF[1] * 0.997 => pad2a.freq; padF[1] * (1.003 - drift) => pad2b.freq;
        padF[2] * 0.998 => pad3a.freq; padF[2] * (1.002 + drift * 0.7) => pad3b.freq;
        shimF[0] => shim1.freq; shimF[1] => shim2.freq; shimF[2] * 1.001 => shim3.freq;

        // Shimmer: very slow fade in/out
        shimAmpCurrent + (shimAmpTarget - shimAmpCurrent) * 0.003 => shimAmpCurrent;
        shimAmpCurrent => shimG.gain;
        if(shimAmpTarget > 0.002) shimAmpTarget * 0.9999 => shimAmpTarget;

        // Strings: very slow attack and release — bowed, cinematic
        strAmpCurrent + (strAmpTarget - strAmpCurrent) * 0.008 => strAmpCurrent;
        strAmpCurrent => strG.gain;
        if(strAmpTarget > 0.002) strAmpTarget * 0.9994 => strAmpTarget;
        strFilt.freq() + (strFiltTarget - strFilt.freq()) * 0.002 => strFilt.freq;
        if(strFiltTarget > 1200.0) strFiltTarget * 0.99998 => strFiltTarget;
        // Slow detune drift for living string feel
        strF1 + (strT1 - strF1) * 0.06 => strF1;
        strF2 + (strT2 - strF2) * 0.06 => strF2;
        strF1 * 0.999 => str1a.freq; strF1 * (1.001 + 0.0008 * Math.sin(stepCount * 0.0013)) => str1b.freq;
        strF2 * 0.998 => str2a.freq; strF2 * (1.002 - 0.0008 * Math.sin(stepCount * 0.0009)) => str2b.freq;

        // Melody: layer gate (fast in, slow out) + per-voice soft-attack bell envelopes
        if(arpAmpTarget > arpAmpCurrent) arpAmpCurrent + (arpAmpTarget - arpAmpCurrent) * 0.05 => arpAmpCurrent;
        else arpAmpCurrent + (arpAmpTarget - arpAmpCurrent) * 0.006 => arpAmpCurrent;
        arpAmpCurrent => arpG.gain;
        for(0 => int i; i < 2; i++) {
            if(arpAtk[i]) {
                arpEnv[i] + (arpPeak[i] - arpEnv[i]) * 0.35 => arpEnv[i];
                if(arpEnv[i] >= arpPeak[i] * 0.95) 0 => arpAtk[i];
            } else arpEnv[i] * 0.982 => arpEnv[i];
            arpEnv[i] => arpEnvG[i].gain;
        }

        // Texture breath
        texAmpCurrent + (texAmpTarget - texAmpCurrent) * 0.003 => texAmpCurrent;
        texAmpCurrent => texG.gain;
        if(texAmpTarget > 0.001) texAmpTarget * 0.9994 => texAmpTarget;

        // Rumble: slow throb with filter movement
        rumbleAmpCurrent + (rumbleAmpTarget - rumbleAmpCurrent) * 0.002 => rumbleAmpCurrent;
        rumbleAmpCurrent => rumbleG.gain;
        // Throb: sine frequency pulses slowly for unease
        28.0 + 8.0 * Math.sin(stepCount * 0.0006) => rumbleSin.freq;
        // Filter creeps up during tension, adds presence
        40.0 + 40.0 * Math.sin(stepCount * 0.0004) => rumbleFilt.freq;

        // FX: smooth HPF back toward 20Hz when not active (skip during intro + HPF sweep)
        if(fxType != 1 && !introActive) fxHPF.freq() + (20.0 - fxHPF.freq()) * 0.02 => fxHPF.freq;

        // Master
        masterGain + (masterTarget - masterGain) * 0.006 => masterGain;
        masterGain * volume => master.gain;

        stepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
