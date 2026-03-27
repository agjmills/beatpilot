// ambient.ck - Beatpilot Ambient Engine
// No drums. Evolving pads, warm drones, shimmering textures, all in space.

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
Gain master => Gain dryOut => dac;
0.0 => master.gain;

// Multi-tap delay reverb — 4 taps with feedback for diffuse wash
master => DelayL rv1 => Gain rvFb1 => LPF rvF1 => Gain rvMix => dac;
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

// ============ SCALES ============
// 0: pentatonic major (safe, bright)
// 1: minor pentatonic (mellow)
// 2: harmonic minor (dark, cinematic — that raised 7th)
// 3: phrygian (ominous — half-step root, Zimmer territory)
// 4: minor (natural)
// 5: whole-half diminished (maximum tension)
[[0,2,4,7,9], [0,3,5,7,10], [0,2,3,5,7,8,11], [0,1,3,5,7,8,10], [0,2,3,5,7,8,10], [0,1,3,4,6,7,9,10]] @=> int scales[][];

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    if(degree < 0) return 0;
    return key + octave * 12 + scl[degree % scl.cap()] + (degree / scl.cap()) * 12;
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

// ============ SHIMMER (chord cluster, not single tone) ============
SinOsc shim1 => LPF shimFilt => Gain shimG => master;
SinOsc shim2 => shimFilt;
SinOsc shim3 => shimFilt;
0.2 => shim1.gain; 0.15 => shim2.gain; 0.12 => shim3.gain;
3000.0 => shimFilt.freq; 0.5 => shimFilt.Q;
0.0 => shimG.gain;
0.0 => float shimAmpTarget;
0.0 => float shimAmpCurrent;

// ============ ARPEGGIO (sparse plucks with longer delay wash) ============
SinOsc arp => LPF arpFilt => Gain arpG => master;
800.0 => arpFilt.freq; 0.7 => arpFilt.Q;
0.0 => arpG.gain;
0.0 => float arpAmpTarget;
0.0 => float arpAmpCurrent;
-1 => int lastArpDeg;

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
        [0, 0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 2, 2, 1, 0] @=> int gb[];
        for(0 => int i; i < 16; i++) gb[i] => arrangement[i];
    } else if(arrType == 1) {
        // Wave: builds, strips, builds again
        [0, 1, 2, 3, 3, 2, 1, 0, 0, 1, 2, 3, 3, 3, 2, 1] @=> int wv[];
        for(0 => int i; i < 16; i++) wv[i] => arrangement[i];
    } else {
        // Sparse: mostly minimal with occasional full moments
        [0, 0, 0, 1, 0, 0, 1, 2, 0, 0, 0, 3, 2, 1, 0, 0] @=> int sp[];
        for(0 => int i; i < 16; i++) sp[i] => arrangement[i];
    }
}

// ============ GENERATE ARP LINE ============
// Places chord tones at musical positions across 64 steps (4 bars x 16 steps)
// Sparse: 2-3 notes per bar, consonant with each chord
fun void generateArp() {
    // Clear
    for(0 => int i; i < 64; i++) -1 => arpLine[i];

    // For each of the 4 bars (each bar = 16 steps, each bar has its own chord)
    for(0 => int bar; bar < 4; bar++) {
        bar * 16 => int barStart;
        progs[progIdx][bar % progs[progIdx].cap()] => int root;

        // Chord tones: root, 3rd, 5th relative to chord root in the scale
        [root, root + 2, root + 4] @=> int tones[];

        // Seed-derived pattern: pick 2-3 positions per bar
        // Use seed bits to vary which steps get notes
        (seed + bar * 37) => int barSeed;

        // Position 1: early in the bar (step 1-4)
        1 + (barSeed % 4) => int pos1;
        tones[barSeed % 3] => int tone1;
        tone1 => arpLine[barStart + pos1];

        // Position 2: mid-bar (step 7-11)
        7 + ((barSeed / 3) % 5) => int pos2;
        tones[(barSeed / 5) % 3] => int tone2;
        // Avoid repeating the same tone
        if(tone2 == tone1) tones[(tone2 + 1) % 3] => tone2;
        tone2 => arpLine[barStart + pos2];

        // Position 3: only on some bars (seed-dependent), late (step 12-14)
        if((barSeed % 5) < 3) {
            12 + ((barSeed / 7) % 3) => int pos3;
            tones[(barSeed / 11) % 3] => int tone3;
            tone3 => arpLine[barStart + pos3];
        }
    }
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
            newScale % 4 => scaleType;
            newSeed % 256 => seed;
            seed % progs.cap() => progIdx;
            // Dark progressions (idx 2-5) use dark scales
            if(progIdx >= 2) {
                1 => mood;
                2 + (seed % 4) => scaleType; // harmonic minor, phrygian, minor, diminished
            } else {
                0 => mood;
                seed % 2 => scaleType; // pentatonic major/minor
            }
            0 => phraseBar;
            0 => chordIdx;
            0 => phraseStep;
            progs[progIdx][0] => chordRoot;

            // Generate arp pattern and arrangement from seed
            generateArp();
            generateArrangement();

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

            // Drone always on — set pitch to chord root
            0.06 => droneAmpTarget;
            Std.mtof(note(chordRoot, 2)) => droneCarr.freq;
            droneCarr.freq() * 1.5 => droneMod.freq;
            droneCarr.freq() * 0.998 => droneWarm1.freq;
            droneCarr.freq() * 1.002 => droneWarm2.freq;
            Std.mtof(note(chordRoot, 1)) => subDrone.freq;

            // Arrangement mask gates initial layer targets
            arrangement[0] => int initArr;
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
while(true) {
    stepCount % 16 => int s;

    if(s == 0) {
        readState();
        FileIO vf;
        if(vf.open("/tmp/beatpilot-volume", FileIO.READ)) {
            Std.atoi(vf.readLine()) => int vol;
            vf.close();
            if(vol >= 0 && vol <= 100) vol / 100.0 => volume;
        }
        barsSinceEvent + 1 => barsSinceEvent;

        // Advance chord progression: change every 4 bars
        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) 0 => phraseBar;
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        progs[progIdx][chordIdx] => chordRoot;

        // ---- ARRANGEMENT GATING: control which layers are active ----
        arrangement[phraseBar] => int arrLevel;
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
            // Don't kill arp target mid-note, let it decay naturally
            if(arpAmpCurrent < 0.002) 0.0 => arpAmpTarget;
        }

        // Energy decay
        if(barsSinceEvent > 10 && energy > 0 && !autoActive) {
            energy - 1 => energy;
            0 => barsSinceEvent;
        }

        // Auto-evolution instead of silence
        if(barsSinceEvent > 12 && !autoActive) {
            1 => autoActive;
            1 => autoSection;
            0 => autoSectionBar;
            1 => energy;
            1.0 => masterTarget;
        }

        if(autoActive) {
            autoSectionBar + 1 => autoSectionBar;
            1.0 => masterTarget;

            if(autoSectionBar >= autoSectionLen[autoSection]) {
                0 => autoSectionBar;
                autoNextSection[autoSection] => autoSection;

                if(autoSection == 1) {
                    // Thin: just drone + sub, everything else fades
                    0 => energy;
                    0.07 => droneAmpTarget;
                    0.06 => subAmpTarget;
                    0.0 => padAmpTarget;
                    0.0 => shimAmpTarget;
                    0.0 => arpAmpTarget;
                    0.0 => texAmpTarget;
                    0.0 => rumbleAmpTarget;
                } else if(autoSection == 2) {
                    // Swell: pad comes in slowly, texture breathes
                    1 => energy;
                    0.04 => padAmpTarget;
                    0.006 => texAmpTarget;
                    0.02 => arpAmpTarget;
                } else if(autoSection == 3) {
                    // Shimmer focus: high cluster + arp, pad sustains
                    2 => energy;
                    0.04 => shimAmpTarget;
                    0.03 => arpAmpTarget;
                    0.05 => padAmpTarget;
                    0.01 => texAmpTarget;
                    0.0 => rumbleAmpTarget;
                } else if(autoSection == 4) {
                    // Full return: warm resolution after tension
                    2 => energy;
                    // Shift to a warm scale for the release
                    seed % 2 => scaleType;
                    seed % 2 => progIdx;  // warm progression
                    0.07 => droneAmpTarget;
                    0.05 => padAmpTarget;
                    0.03 => shimAmpTarget;
                    0.03 => arpAmpTarget;
                    0.0 => rumbleAmpTarget;
                } else if(autoSection == 5) {
                    // TENSION: dark mode — drone drops, rumble builds,
                    // switch to dark scale, dissonant intervals
                    1 => mood;
                    2 + (seed % 4) => scaleType;  // harmonic minor/phrygian/etc
                    2 + (seed % 4) => progIdx;     // dark progression
                    0 => phraseBar;
                    1 => energy;
                    // Drone drops an octave, gets louder
                    Std.mtof(note(0, 1)) => droneCarr.freq;
                    droneCarr.freq() * 1.5 => droneMod.freq;
                    droneCarr.freq() * 0.998 => droneWarm1.freq;
                    droneCarr.freq() * 1.002 => droneWarm2.freq;
                    0.09 => droneAmpTarget;
                    0.07 => subAmpTarget;
                    // Rumble builds
                    0.04 => rumbleAmpTarget;
                    // Noise texture swells
                    0.015 => texAmpTarget;
                    // Pad goes dissonant — tritone interval
                    Std.mtof(note(0, 3)) => float t1;
                    Std.mtof(note(3, 3)) => float t2;  // tritone in phrygian
                    Std.mtof(note(1, 3)) => float t3;  // minor 2nd
                    t1 * 0.997 => pad1a.freq; t1 * 1.003 => pad1b.freq;
                    t2 * 0.997 => pad2a.freq; t2 * 1.003 => pad2b.freq;
                    t3 * 0.998 => pad3a.freq; t3 * 1.002 => pad3b.freq;
                    0.03 => padAmpTarget;
                    600.0 => padFiltTarget;  // darker filter
                    0.0 => shimAmpTarget;
                    0.0 => arpAmpTarget;
                } else if(autoSection == 6) {
                    // RELEASE: tension resolves, warm wash
                    0 => mood;
                    seed % 2 => scaleType;
                    seed % 2 => progIdx;
                    0 => phraseBar;
                    2 => energy;
                    // Drone back up
                    Std.mtof(note(0, 2)) => droneCarr.freq;
                    droneCarr.freq() * 1.5 => droneMod.freq;
                    droneCarr.freq() * 0.998 => droneWarm1.freq;
                    droneCarr.freq() * 1.002 => droneWarm2.freq;
                    0.06 => droneAmpTarget;
                    0.05 => subAmpTarget;
                    0.0 => rumbleAmpTarget;
                    0.05 => padAmpTarget;
                    1400.0 => padFiltTarget;
                    0.03 => shimAmpTarget;
                    0.02 => arpAmpTarget;
                    0.005 => texAmpTarget;
                } else {
                    // Normal: cycle restarts
                    1 => energy;
                    0.0 => rumbleAmpTarget;
                }
            }
        }
    }

    // ---- DRONE PITCH: follow chord root smoothly ----
    if(s == 0 && energy >= 0) {
        // During tension sections, drone stays on low root — ominous pedal tone
        if(autoActive && autoSection == 5) {
            Std.mtof(note(0, 1)) => float drTarget;
            droneCarr.freq() + (drTarget - droneCarr.freq()) * 0.02 => droneCarr.freq;
        } else {
            Std.mtof(note(chordRoot, 2)) => float drTarget;
            droneCarr.freq() + (drTarget - droneCarr.freq()) * 0.05 => droneCarr.freq;
        }
        droneCarr.freq() * 1.5 => droneMod.freq;
        droneCarr.freq() * 0.998 => droneWarm1.freq;
        droneCarr.freq() * 1.002 => droneWarm2.freq;
        Std.mtof(note(chordRoot, 1)) => float subTarget;
        subDrone.freq() + (subTarget - subDrone.freq()) * 0.05 => subDrone.freq;
    }

    // ---- PAD CHORD: follows progression, set on chord change ----
    if(arrangement[phraseBar] >= 2 && s == 0 && phraseBar % 4 == 0) {
        Std.mtof(note(chordRoot, 3)) => float p1;
        Std.mtof(note(chordRoot + 2, 3)) => float p2;
        Std.mtof(note(chordRoot + 4, 3)) => float p3;
        // Detuned pairs — slow drift applied in substep
        p1 * 0.997 => pad1a.freq; p1 * 1.003 => pad1b.freq;
        p2 * 0.997 => pad2a.freq; p2 * 1.003 => pad2b.freq;
        p3 * 0.998 => pad3a.freq; p3 * 1.002 => pad3b.freq;
        1400.0 + Math.random2f(0.0, 400.0) => padFiltTarget;
    }

    // ---- SHIMMER CLUSTER: triad an octave above pad ----
    if(arrangement[phraseBar] >= 3 && s == 0 && phraseBar % 8 == 0) {
        Std.mtof(note(chordRoot, 5)) => float s1;
        Std.mtof(note(chordRoot + 2, 5)) => float s2;
        Std.mtof(note(chordRoot + 4, 5)) => float s3;
        s1 => shim1.freq;
        s2 => shim2.freq;
        s3 * 1.001 => shim3.freq; // tiny detune for width
    }

    // ---- ARPEGGIO: follows arpLine pattern instead of random dice ----
    if(arpLine[phraseStep] >= 0 && arrangement[phraseBar] >= 3) {
        arpLine[phraseStep] => int arpDeg;
        if(arpDeg != lastArpDeg || arpAmpCurrent < 0.004) {
            arpDeg => lastArpDeg;
            3 + ((seed + phraseStep) % 2) => int arpOct;
            Std.mtof(note(arpDeg, arpOct)) => arp.freq;
            0.025 => arpAmpTarget;
        }
    }

    // ---- TEXTURE: noise breath, gated by arrangement ----
    if(arrangement[phraseBar] >= 2 && s == 0 && Math.random2(0, 3) == 0) {
        300.0 + Math.random2f(0.0, 600.0) => texBP.freq;
        0.008 => texAmpTarget;
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

        // Sub drone
        subAmpCurrent + (subAmpTarget - subAmpCurrent) * 0.003 => subAmpCurrent;
        subAmpCurrent => subG.gain;

        // Pad: breathing amplitude + filter LFO
        padBreathPhase + 0.0008 => padBreathPhase;
        padLfoPhase + 0.0012 => padLfoPhase;
        // Amplitude breathes slowly
        padAmpTarget * (0.85 + 0.15 * Math.sin(padBreathPhase)) => float padBreathGain;
        padAmpCurrent + (padBreathGain - padAmpCurrent) * 0.005 => padAmpCurrent;
        padAmpCurrent => padG.gain;
        // Note: padAmpTarget is set per-bar by arrangement gating with phrase dynamics
        // Filter sweeps slowly
        Math.sin(padLfoPhase) * 300.0 => float padLfoMod;
        padFilt.freq() + ((padFiltTarget + padLfoMod) - padFilt.freq()) * 0.008 => padFilt.freq;
        if(padFiltTarget > 500.0) padFiltTarget * 0.99998 => padFiltTarget;

        // Pad detune drift: very slow pitch wobble on b oscillators
        0.0001 => float driftRate;
        pad1b.freq() * (1.0 + 0.0002 * Math.sin(stepCount * driftRate * 1.1)) => pad1b.freq;
        pad2b.freq() * (1.0 + 0.0002 * Math.sin(stepCount * driftRate * 0.9)) => pad2b.freq;
        pad3b.freq() * (1.0 + 0.0002 * Math.sin(stepCount * driftRate * 1.3)) => pad3b.freq;

        // Shimmer: very slow fade in/out
        shimAmpCurrent + (shimAmpTarget - shimAmpCurrent) * 0.003 => shimAmpCurrent;
        shimAmpCurrent => shimG.gain;
        if(shimAmpTarget > 0.002) shimAmpTarget * 0.9999 => shimAmpTarget;

        // Arp: quick attack, slow decay for pluck feel
        arpAmpCurrent + (arpAmpTarget - arpAmpCurrent) * 0.02 => arpAmpCurrent;
        arpAmpCurrent => arpG.gain;
        if(arpAmpTarget > 0.002) arpAmpTarget * 0.994 => arpAmpTarget;

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

        // Master
        masterGain + (masterTarget - masterGain) * 0.006 => masterGain;
        masterGain * volume => master.gain;

        stepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
