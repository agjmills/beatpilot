// lofi.ck - Beatpilot Lo-fi / Chillhop Engine
// 85 BPM, mellow, jazzy, dusty

// ============ CLOCK ============
85.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;
4 => int SUBSTEPS;
0.63 => float swingAmt; // heavy swing — lofi lives on shuffle

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
0 => int variant;

// ============ PHRASE / CHORD PROGRESSION ============
// Jazzy progressions: ii-V-I-vi, I-vi-ii-V, etc.
[[0, 2, 4, 3], [0, 4, 1, 3], [2, 4, 0, 3], [0, 3, 2, 4], [0, 1, 3, 4]] @=> int progs[][];
0 => int progIdx;
0 => int chordIdx;
0 => int chordRoot;
0 => int phraseBar;

// ============ LEAD MOTIF (4-bar phrase — sparse, melodic) ============
64 => int PHRASE_LEN;
int motif[64];          // lead: scale degrees per step (-1 = rest)
int bassLine[64];       // bass: scale degrees per step (-1 = rest)
0 => int motifGenerated;
0 => int phraseStep;    // current position in the 64-step phrase (shared by bass + lead)

// Arrangement mask: which bars (0-15) have which layers active
// 0=nothing, 1=bass only, 2=bass+keys, 3=bass+keys+lead
int arrangement[16];

fun void generateMotif() {
    seed => int s;
    for(0 => int i; i < PHRASE_LEN; i++) -1 => motif[i];

    // --- CELL-BASED COMPOSITION ---
    // Generate a short 2-3 note cell, then repeat/transpose/vary it.
    // Repetition = composed. Random = cat on keyboard.

    // Cell: defined as intervals from a starting degree + rhythm
    // e.g., [0, +2, -1] starting on degree 0 = play 0, 2, 1
    int cellDeg[3];    // scale degrees in the cell
    int cellPos[3];    // step positions within a half-bar (0-7)

    // Seed determines the cell shape
    0 => cellDeg[0];                           // always start on a chord tone
    [1, 2, -1, 2, 1, -2] @=> int leaps[];
    leaps[s % leaps.cap()] => int leap1;
    leap1 => cellDeg[1];                       // first interval
    // Third note: approach back toward start or continue
    [-1, 0, 1, -1, 0] @=> int resolves[];
    cellDeg[1] + resolves[(s / 2) % resolves.cap()] => cellDeg[2];

    // Cell rhythm: where the 3 notes sit within an 8-step group
    [[0, 4, 6], [0, 2, 6], [0, 4, 8], [2, 4, 6], [0, 6, 8]] @=> int cellRhythms[][];
    cellRhythms[(s / 3) % cellRhythms.cap()] @=> int cR[];
    cR[0] => cellPos[0]; cR[1] => cellPos[1]; cR[2] => cellPos[2];

    // Variation type for bar 2: seed picks
    s % 3 => int varType; // 0=transpose up, 1=invert, 2=retrograde

    // --- Bar 1 (steps 0-15): play the cell, then silence ---
    for(0 => int i; i < 3; i++) {
        cellDeg[i] => motif[cellPos[i]];
    }

    // --- Bar 2 (steps 16-31): cell VARIED ---
    if(varType == 0) {
        // Transpose: same shape, up a 3rd (2 degrees)
        for(0 => int i; i < 3; i++) {
            cellDeg[i] + 2 => motif[16 + cellPos[i]];
        }
    } else if(varType == 1) {
        // Invert: flip intervals (what went up goes down)
        cellDeg[0] => motif[16 + cellPos[0]];
        cellDeg[0] - leap1 => motif[16 + cellPos[1]];
        cellDeg[0] - leap1 - resolves[(s / 2) % resolves.cap()] => motif[16 + cellPos[2]];
    } else {
        // Retrograde: play cell backwards
        for(0 => int i; i < 3; i++) {
            cellDeg[2 - i] + 1 => motif[16 + cellPos[i]];
        }
    }

    // --- Bar 3 (steps 32-47): cell TWICE (compressed), reaching higher ---
    // First half: cell transposed up
    for(0 => int i; i < 3; i++) {
        cellDeg[i] + 3 => motif[32 + cellPos[i]];
    }
    // Second half: cell original, shifted later in bar
    // Use approach note before the first cell note
    cellDeg[0] - 1 => motif[32 + 8]; // approach note from below
    for(0 => int i; i < 2; i++) {
        cellDeg[i] => motif[32 + 10 + i * 2];
    }

    // --- Bar 4 (steps 48-63): half cell + resolve to root ---
    // Just the first interval of the cell, then land on root
    cellDeg[0] + 1 => motif[48];     // pickup
    cellDeg[1] => motif[52];          // first leap
    0 => motif[60];                   // resolve to root — always

    // --- BASS LINE: derived from the same cell ---
    // Lofi bass is warm and simple — even sparser than techno.
    // Root on strong beats, cell's first interval as passing tone.
    for(0 => int i; i < PHRASE_LEN; i++) -1 => bassLine[i];

    // Bar 1: root + one passing tone (gentle, establishing)
    0 => bassLine[0];
    cellDeg[1] => bassLine[8];

    // Bar 2: transposed matching cell variation
    if(varType == 0) {
        2 => bassLine[16]; cellDeg[1] + 2 => bassLine[24];
    } else if(varType == 1) {
        0 => bassLine[16]; 0 - leap1 => bassLine[24];
    } else {
        1 => bassLine[16]; cellDeg[2] + 1 => bassLine[24];
    }

    // Bar 3: slightly busier — root, passing tone, another root
    0 => bassLine[32]; cellDeg[1] => bassLine[36];
    0 => bassLine[40]; cellDeg[2] => bassLine[44];

    // Bar 4: just roots — resolving, minimal
    0 => bassLine[48];
    0 => bassLine[56];

    // --- ARRANGEMENT: which bars have which layers ---
    // 16-bar phrase with structure — lofi breathes, layers come and go
    // 0=nothing, 1=bass only, 2=bass+keys, 3=bass+keys+lead
    s % 3 => int arrType;
    if(arrType == 0) {
        // Build: bass -> +keys -> +lead -> strip back
        [1,1,1,1, 2,2,2,2, 3,3,3,3, 2,2,1,1] @=> int arrA[];
        for(0 => int i; i < 16; i++) arrA[i] => arrangement[i];
    } else if(arrType == 1) {
        // Call-response: lead bars alternate with bass-only
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

// ============ AUTO-EVOLUTION ============
0 => int autoSection;
0 => int autoSectionBar;
0 => int autoActive;
[0, 10, 8, 6, 2] @=> int autoSectionLen[];
[1, 2, 3, 4, 0] @=> int autoNextSection[];

// ============ MASTER BUS + REVERB ============
Gain master => Gain dryOut => dac;
0.0 => master.gain;
// Warm reverb — longer tails for lofi
master => DelayL rv1 => Gain rvFb1 => LPF rvF1 => Gain rvMix => dac;
master => DelayL rv2 => Gain rvFb2 => LPF rvF2 => rvMix;
master => DelayL rv3 => Gain rvFb3 => LPF rvF3 => rvMix;
master => DelayL rv4 => Gain rvFb4 => LPF rvF4 => rvMix;
rvFb1 => rv3; rvFb2 => rv4; rvFb3 => rv1; rvFb4 => rv2;
0.18::second => rv1.max; 0.1573::second => rv1.delay;
0.25::second => rv2.max; 0.2137::second => rv2.delay;
0.32::second => rv3.max; 0.2891::second => rv3.delay;
0.42::second => rv4.max; 0.3719::second => rv4.delay;
0.42 => rvFb1.gain; 0.40 => rvFb2.gain; 0.38 => rvFb3.gain; 0.36 => rvFb4.gain;
2000.0 => rvF1.freq; 1800.0 => rvF2.freq; 1500.0 => rvF3.freq; 1300.0 => rvF4.freq;
0.22 => rvMix.gain;
0.78 => dryOut.gain;

// Jazzier scales: major 7, minor 7, dorian, lydian
[[0,2,4,7,11], [0,3,5,7,10], [0,2,3,5,9], [0,2,4,6,7]] @=> int scales[][];

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    if(degree < 0) return 0;
    return key + octave * 12 + scl[degree % scl.cap()] + (degree / scl.cap()) * 12;
}

// ============ VELOCITY MAPS ============
[1.0, 0.0, 0.5, 0.0, 0.9, 0.0, 0.4, 0.0, 0.95, 0.0, 0.45, 0.0, 0.85, 0.0, 0.55, 0.3] @=> float kickVel[];
[0.7, 0.25, 0.5, 0.25, 0.8, 0.25, 0.5, 0.3, 0.7, 0.25, 0.5, 0.25, 0.8, 0.3, 0.5, 0.35] @=> float hatVel[];

// ============ KICK (soft, round) ============
SinOsc kickOsc => LPF kickLPF => Gain kickG => master;
0.0 => kickOsc.gain;
200.0 => kickLPF.freq;
0.25 => kickG.gain;
0.0 => float kickPh;

[[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0],
 [1,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0]] @=> int kPat[][];

// ============ SNARE (brushy) ============
Noise snN => BPF snBP => ADSR snEnv => Gain snG => master;
2200.0 => snBP.freq; 0.8 => snBP.Q;
snEnv.set(1::ms, 100::ms, 0.02, 60::ms);
0.0 => snG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0]] @=> int snPat[][];

// Ghost brush hits
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,1],
 [0,0,1,0,0,0,0,1,0,0,1,0,0,0,0,1]] @=> int snGhost[][];

// ============ HATS (soft, shuffled) ============
Noise chN => BPF chBP => ADSR chEnv => Gain chG => master;
3500.0 => chBP.freq; 1.2 => chBP.Q;
chEnv.set(0.5::ms, 25::ms, 0.0, 10::ms);
0.03 => chG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0]] @=> int chPat[][];

// ============ BASS (warm sine, follows chords) ============
SinOsc bassOsc => LPF bassFilt => Gain bassG => master;
0.6 => bassOsc.gain;
600.0 => bassFilt.freq; 1.5 => bassFilt.Q;
0.0 => bassG.gain;
0.0 => float bassAmpTarget;
0.0 => float bassAmpCurrent;

600.0 => float bassFiltTarget;

// ============ KEYS (ModalBar — vibraphone, jazzy shimmer) ============
ModalBar key1 => LPF keyFilt => Gain keyG => master;
ModalBar key2 => keyFilt;
ModalBar key3 => keyFilt;
ModalBar key4 => keyFilt; // 7th voice for jazzy color
1 => key1.preset; 1 => key2.preset; 1 => key3.preset; 1 => key4.preset; // vibraphone
3500.0 => keyFilt.freq; 0.5 => keyFilt.Q;
0.0 => keyG.gain;
0.0 => float keyAmpTarget;
0.0 => float keyAmpCurrent;
3500.0 => float keyFiltTarget;
0.0 => float keyLfoPhase;

// ============ LEAD (Rhodey electric piano — the classic lofi melodic voice) ============
Rhodey ldRhodey => LPF ldFilt => Gain ldDry => master;
1800.0 => ldFilt.freq; 0.7 => ldFilt.Q;
0.0 => ldDry.gain;
1800.0 => float ldFiltTarget;
0.0 => float ldAmpTarget;
0.0 => float ldAmpCurrent;

// Lead delay: quarter note for lofi feel
ldDry => DelayL ldDly => Gain ldDlyFb => LPF ldDlyF => master;
ldDlyFb => ldDly;
(stepDur * 4) => ldDly.max => ldDly.delay; // quarter note delay
0.35 => ldDlyFb.gain;
0.04 => ldDly.gain;
1800.0 => ldDlyF.freq; // darker delay for warmth

// ============ VINYL CRACKLE ============
Noise vinyl => BPF vinylBP => Gain vinylG => master;
1800.0 => vinylBP.freq; 0.5 => vinylBP.Q;
0.0 => vinylG.gain;

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
            progs[progIdx][0] => chordRoot;
            generateMotif();

            newEnergy => energy;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;
            1.0 => masterTarget;

            // Cancel auto-evolution
            if(autoActive) {
                0 => autoActive;
                0 => autoSection;
                0 => autoSectionBar;
            }

            if(energy >= 1) {
                0.06 => snG.gain;
                0.10 => bassG.gain;
                0.007 => vinylG.gain;
            }
            if(energy >= 2) {
                0.05 => keyAmpTarget;
            } else {
                0.0 => keyAmpTarget;
            }
        }
    }
}

// ============ MAIN SEQUENCER ============
while(true) {
    stepCount % 16 => int s;

    if(s == 0) {
        readState();
        barsSinceEvent + 1 => barsSinceEvent;

        // Advance chord progression
        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) 0 => phraseBar;
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        progs[progIdx][chordIdx] => chordRoot;

        // Energy decay
        if(barsSinceEvent > 8 && energy > 0 && !autoActive) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) 0.0 => keyAmpTarget;
            if(energy < 1) {
                0.0 => snG.gain;
                0.0 => bassG.gain;
                0.0 => vinylG.gain;
                0.0 => ldAmpTarget;
            }
        }

        // Auto-evolution
        if(barsSinceEvent > 10 && !autoActive) {
            1 => autoActive;
            1 => autoSection;
            0 => autoSectionBar;
            2 => energy;
            1.0 => masterTarget;
        }

        if(autoActive) {
            autoSectionBar + 1 => autoSectionBar;
            1.0 => masterTarget;

            if(autoSectionBar >= autoSectionLen[autoSection]) {
                0 => autoSectionBar;
                autoNextSection[autoSection] => autoSection;

                if(autoSection == 1) {
                    // Strip back: just bass + vinyl + keys fading
                    1 => energy;
                    0.0 => snG.gain;
                    0.08 => bassG.gain;
                    0.008 => vinylG.gain;
                    0.02 => keyAmpTarget;
                    0.0 => ldAmpTarget;
                } else if(autoSection == 2) {
                    // Rebuild: drums come in, keys swell
                    2 => energy;
                    0.05 => snG.gain;
                    0.10 => bassG.gain;
                    0.05 => keyAmpTarget;
                    generateMotif();
                } else if(autoSection == 3) {
                    // Full: everything, lead comes in
                    2 => energy;
                    0.06 => snG.gain;
                    0.05 => keyAmpTarget;
                } else if(autoSection == 4) {
                    // Swell moment
                    2 => energy;
                    0.06 => keyAmpTarget;
                    1200.0 => keyFiltTarget;
                } else {
                    2 => energy;
                }
            }
        }
    }

    // ---- KICK (soft, with velocity) ----
    if(kPat[energy][s]) {
        0.0 => kickPh;
        0.4 + 0.2 * kickVel[s] => kickOsc.gain;
    }

    // ---- SNARE (brush + ghost) ----
    if(snPat[energy][s]) {
        0.05 + 0.03 * hatVel[s] => snG.gain;
        snEnv.keyOn();
    } else if(snGhost[energy][s]) {
        0.02 => snG.gain;
        snEnv.keyOn();
    }

    // ---- HATS (with velocity) ----
    if(chPat[energy][s]) {
        0.015 + 0.025 * hatVel[s] => chG.gain;
        chEnv.keyOn();
    }

    // ---- ARRANGEMENT: determine what plays this bar ----
    0 => int arrLevel;
    if(motifGenerated) arrangement[phraseBar] => arrLevel;
    if(energy < 2) { if(arrLevel > 1) 1 => arrLevel; }

    // ---- BASS (cell-derived, follows arrangement) ----
    if(energy >= 1 && arrLevel >= 1 && motifGenerated) {
        bassLine[phraseStep % PHRASE_LEN] => int bDeg;
        if(bDeg >= 0) {
            (bDeg + chordRoot) % 5 => bDeg;
            if(bDeg < 0) bDeg + 5 => bDeg;
            Std.mtof(note(bDeg, 2)) => bassOsc.freq;
            // Bass filter: gentle, opens slightly in bar 3
            if(phraseStep >= 32 && phraseStep < 48) {
                800.0 + Math.random2f(0.0, 200.0) => bassFiltTarget;
            } else {
                500.0 + Math.random2f(0.0, 100.0) => bassFiltTarget;
            }
            0.10 => bassAmpTarget;
        }
    }

    // ---- KEYS (ModalBar vibraphone, follows arrangement + phrase dynamics) ----
    if(s == 0 && arrLevel >= 2) {
        Std.mtof(note(chordRoot, 3)) => key1.freq;
        Std.mtof(note(chordRoot + 2, 3)) => key2.freq;
        Std.mtof(note(chordRoot + 4, 3)) => key3.freq;
        Std.mtof(note(chordRoot + 6, 3)) => key4.freq; // jazzy 7th
        0.45 => key1.strikePosition;
        0.5 => key2.strikePosition;
        0.55 => key3.strikePosition;
        0.4 => key4.strikePosition;
        0.6 => key1.strike;
        0.6 => key2.strike;
        0.5 => key3.strike;
        0.45 => key4.strike;
        // Keys dynamics follow phrase position: swell bars 1-2, peak bar 3, pull back bar 4
        phraseBar % 4 => int barInChord;
        if(barInChord < 2) 0.04 => keyAmpTarget;       // bars 1-2: gentle
        else if(barInChord == 2) 0.08 => keyAmpTarget;  // bar 3: peak
        else 0.03 => keyAmpTarget;                       // bar 4: pull back
        if(energy >= 3) keyAmpTarget * 1.3 => keyAmpTarget;
        2800.0 + barInChord * 200.0 => keyFiltTarget;   // filter opens through phrase
    } else if(arrLevel < 2) {
        0.0 => keyAmpTarget;
    }

    // ---- LEAD (cell motif, Rhodey electric piano, follows arrangement) ----
    if(motifGenerated && arrLevel >= 3) {
        motif[phraseStep % PHRASE_LEN] => int deg;
        if(deg >= 0) {
            (deg + chordRoot) % 5 => deg;
            if(deg < 0) deg + 5 => deg;
            4 => int ldOct;
            Std.mtof(note(deg, ldOct)) => ldRhodey.freq;
            // Velocity: phrase contour via noteOn velocity
            phraseStep % 16 => int localStep;
            0.35 => float ldVel;
            if(localStep % 4 == 0) 0.5 => ldVel;
            if(phraseStep >= 32 && phraseStep < 48) ldVel * 1.15 => ldVel;
            if(phraseStep >= 48) ldVel * 0.6 => ldVel;
            ldVel => ldRhodey.noteOn;
            1800.0 + Math.random2f(0.0, 400.0) => ldFiltTarget;
            0.05 => ldAmpTarget;
        }
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
        // Kick: softer, rounder envelope
        if(kickOsc.gain() > 0.005) {
            45.0 + 50.0 * Math.exp(-kickPh * 6.0) => kickOsc.freq;
            kickOsc.freq() * 3.0 => kickLPF.freq;
            kickOsc.gain() * 0.96 => kickOsc.gain;
            kickPh + 0.06 => kickPh;
        } else { 0.0 => kickOsc.gain; }

        // Bass amplitude + filter
        bassAmpCurrent + (bassAmpTarget - bassAmpCurrent) * 0.04 => bassAmpCurrent;
        bassAmpCurrent => bassG.gain;
        if(bassAmpTarget > 0.01) bassAmpTarget * 0.997 => bassAmpTarget;
        bassFilt.freq() + (bassFiltTarget - bassFilt.freq()) * 0.08 => bassFilt.freq;
        if(bassFiltTarget > 400.0) bassFiltTarget * 0.998 => bassFiltTarget;

        // Keys: filter LFO — Wurley handles timbre, we just shape brightness
        keyLfoPhase + 0.0008 => keyLfoPhase;
        keyAmpCurrent + (keyAmpTarget - keyAmpCurrent) * 0.008 => keyAmpCurrent;
        keyAmpCurrent => keyG.gain;
        if(keyAmpTarget > 0.005) keyAmpTarget * 0.9992 => keyAmpTarget;
        Math.sin(keyLfoPhase) * 150.0 => float keyLfoMod;
        keyFilt.freq() + ((keyFiltTarget + keyLfoMod) - keyFilt.freq()) * 0.008 => keyFilt.freq;
        if(keyFiltTarget > 2000.0) keyFiltTarget * 0.99995 => keyFiltTarget;

        // Lead Rhodey envelope — Rhodey has its own decay, we just control the gain bus
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.03 => ldAmpCurrent;
        ldAmpCurrent => ldDry.gain;
        if(ldAmpTarget > 0.003) ldAmpTarget * 0.993 => ldAmpTarget;
        ldFilt.freq() + (ldFiltTarget - ldFilt.freq()) * 0.02 => ldFilt.freq;
        if(ldFiltTarget > 600.0) ldFiltTarget * 0.999 => ldFiltTarget;

        // Master
        masterGain + (masterTarget - masterGain) * 0.015 => masterGain;
        masterGain => master.gain;

        thisStepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
