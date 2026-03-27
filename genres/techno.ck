// engine.ck - Beatpilot Techno Engine
// A continuous techno groove that evolves based on Claude hook events.
// Reads state from /tmp/beatpilot-state (written by hook.sh).
// Energy (0-3) controls which layers are active and pattern intensity.
// Transitions: drops, risers, fills, and breakdowns triggered by events.

// ============ CLOCK ============
128.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;
4 => int SUBSTEPS;
0.62 => float swingAmt; // 0.5 = straight, 0.67 = heavy shuffle, 0.62 = nice groove

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

// ============ PHRASE / SONG STRUCTURE ============
// Chord progression: 4 chords, each lasts 4 bars = 16-bar phrase
// Progressions are arrays of root scale degrees
[[0, 3, 4, 2], [0, 4, 3, 1], [0, 2, 3, 4], [0, 1, 3, 2]] @=> int progs[][];
0 => int progIdx;       // which progression (set by seed)
0 => int chordIdx;      // current chord in progression (0-3)
0 => int chordRoot;     // current chord root degree
0 => int phraseBar;     // bar within 16-bar phrase (0-15)

// Lead motif: 4-bar phrase (64 steps) with melodic contour
// Bar 1: call (short figure), Bar 2: response (variation),
// Bar 3: development (higher/busier), Bar 4: resolution (back to root)
64 => int PHRASE_LEN;
int motif[64];          // scale degrees per step (-1 = rest)
0 => int motifGenerated;
0 => int phraseStep;    // current position in the 64-step phrase

fun void generateMotif() {
    seed => int s;

    // Start with all rests
    for(0 => int i; i < PHRASE_LEN; i++) {
        -1 => motif[i];
    }

    // Build a 4-note core figure from seed
    int fig[4];
    0 => fig[0];                    // start on root
    (s % 3 + 1) => fig[1];         // step up (1-3)
    (s % 2 + 2) => fig[2];         // higher (2-3)
    ((s / 2) % 2) => fig[3];       // resolve toward root (0-1)

    // Bar 1 (steps 0-15): call — place the core figure
    fig[0] => motif[0];
    fig[1] => motif[4];
    fig[2] => motif[(s % 2 + 6)];
    fig[3] => motif[12];

    // Bar 2 (steps 16-31): response — same rhythm, transposed up
    fig[0] + 2 => motif[16];
    fig[1] + 2 => motif[20];
    fig[2] + 1 => motif[(s % 2 + 22)];
    fig[0] + 1 => motif[28];

    // Bar 3 (steps 32-47): development — busier, higher register
    fig[2] => motif[32];
    fig[1] + 2 => motif[34];
    fig[2] + 2 => motif[36];
    fig[3] + 3 => motif[38];
    fig[0] + 2 => motif[40];
    fig[1] => motif[44];

    // Bar 4 (steps 48-63): resolution — sparse, descend to root
    fig[2] => motif[48];
    fig[1] => motif[52];
    fig[3] => motif[56];
    0 => motif[60];                 // land on root

    // Add seed-based ghost notes for variation (low probability hits)
    for(0 => int i; i < 6; i++) {
        (s * (i + 7) + i * 53) % PHRASE_LEN => int pos;
        if(motif[pos] < 0 && pos % 2 != 0) {
            // Only on off-beats, and make them neighbors of nearby notes
            (s + i) % 4 => motif[pos];
        }
    }

    0 => phraseStep;
    1 => motifGenerated;
}

// ============ TRANSITION STATE ============
// 0=none, 1=riser (building), 2=drop (kick out, tension), 3=impact (kick back hard)
0 => int transition;
0 => int transitionBars;   // bars remaining in current transition
0 => int transitionStep;   // steps into transition
0 => int lastTransitionTs; // prevent overlapping transitions

// ============ AUTO-EVOLUTION (idle sections) ============
// When Claude is working on a long task, cycle through musical sections
// instead of just decaying to silence.
// Sections: 0=normal, 1=breakdown (strip to pad+hats), 2=ambient (pad only, half-feel),
//           3=build (riser + hats intensify), 4=drop (everything slams back)
0 => int autoSection;
0 => int autoSectionBar;   // bars into current auto section
0 => int autoActive;       // whether auto-evolution is running
// Section durations in bars
[0, 8, 6, 4, 1] @=> int autoSectionLen[];
// Cycle order
[1, 2, 3, 4, 0] @=> int autoNextSection[];

// ============ MASTER BUS ============
Gain master => dac;
0.0 => master.gain;

// ============ SCALES ============
[[0,2,4,7,9], [0,3,5,7,10], [0,2,4,5,7], [0,2,3,7,10]] @=> int scales[][];

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    if(degree < 0) return 0;
    return key + octave * 12 + scl[degree % scl.cap()] + (degree / scl.cap()) * 12;
}

// ============ KICK ============
SinOsc kickOsc => LPF kickLPF => Gain kickG => master;
0.0 => kickOsc.gain;
300.0 => kickLPF.freq;
0.35 => kickG.gain;
0.0 => float kickPh;
// Click transient for punch
Noise kickClick => BPF kickClickBP => ADSR kickClickEnv => kickG;
3500.0 => kickClickBP.freq; 1.5 => kickClickBP.Q;
kickClickEnv.set(0.2::ms, 8::ms, 0.0, 3::ms);
0.3 => kickClick.gain;

[[1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,1,0]] @=> int kPat[][];

// ============ VELOCITY MAPS ============
// Hat velocity: accents on beats, ghost notes on off-beats (0.0-1.0)
[1.0, 0.3, 0.7, 0.3, 1.0, 0.3, 0.7, 0.4, 1.0, 0.3, 0.7, 0.3, 1.0, 0.35, 0.7, 0.5] @=> float hatVel[];
// Kick velocity: beat 1 hardest, slight variation
[1.0, 0.0, 0.0, 0.0, 0.9, 0.0, 0.0, 0.0, 0.95, 0.0, 0.0, 0.0, 0.85, 0.0, 0.8, 0.0] @=> float kickVel[];

// ============ CLOSED HAT ============
Noise chN => HPF chHP => ADSR chEnv => Gain chG => master;
8000.0 => chHP.freq;
chEnv.set(0.3::ms, 22::ms, 0.0, 5::ms);
0.07 => chG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0]] @=> int chPat[][];

// ============ OPEN HAT ============
Noise ohN => BPF ohBP => ADSR ohEnv => Gain ohG => master;
9000.0 => ohBP.freq; 1.5 => ohBP.Q;
ohEnv.set(1::ms, 150::ms, 0.03, 100::ms);
0.05 => ohG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
 [0,0,0,0,0,0,0,1,0,0,0,1,0,0,1,0]] @=> int ohPat[][];

// ============ BASS ============
TriOsc bassOsc => LPF bassF => Gain bassG => master;
0.6 => bassOsc.gain;
200.0 => bassF.freq; 4.0 => bassF.Q;
0.12 => bassG.gain;
200.0 => float bassFiltTarget;

[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1,-1,-1, 0,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1, 0,-1,-1, 3,-1, 0,-1,-1,-1,-1, 4, 0,-1],
 [ 0,-1, 5,-1, 0,-1,-1, 3, 0,-1,-1, 7, 0,-1, 5,-1]] @=> int bPatA[][];

[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1, 0,-1,-1,-1,-1,-1, 0,-1,-1,-1],
 [ 0,-1, 0,-1,-1, 4,-1,-1,-1, 0,-1,-1, 3,-1,-1, 0],
 [ 0, 5,-1, 0,-1, 3,-1, 7,-1, 0,-1, 5, 0,-1, 3,-1]] @=> int bPatB[][];

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [1,0,0,1,0,0,1,0,1,0,0,0,0,1,0,0],
 [1,0,1,0,1,0,0,1,1,0,0,1,0,1,0,1]] @=> int bAcc[][];

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0],
 [0,0,1,0,0,0,0,0,0,0,0,1,0,0,1,0]] @=> int bOctUp[][];

// ============ LEAD ============
// Sine fundamental + quiet octave harmonic = clean, bell-like tone
SinOsc ldOsc1 => LPF ldF => Gain ldDry => master;
SinOsc ldOsc2 => ldF;  // octave up, quieter
0.5 => ldOsc1.gain; 0.18 => ldOsc2.gain;
2800.0 => ldF.freq; 0.8 => ldF.Q; // gentle roll-off, not aggressive
0.0 => ldDry.gain;
2800.0 => float ldFiltTarget;
0.0 => float ldAmpTarget;
0.0 => float ldAmpCurrent;
-1 => int lastLeadDeg;

// Lead delay: dotted-eighth feedback delay for rhythmic echoes
ldDry => Delay ldDly1 => Gain ldDlyFb => LPF ldDlyF => master;
ldDlyFb => ldDly1; // feedback loop
(stepDur * 3) => ldDly1.max => ldDly1.delay; // dotted eighth = 3 steps
0.45 => ldDlyFb.gain;   // feedback amount — decays over ~3 repeats
0.04 => ldDly1.gain;    // wet level
2500.0 => ldDlyF.freq;  // darken repeats

// ============ PAD ============
TriOsc padOsc1 => LPF padF => Gain padG => master;
SinOsc padOsc2 => padF;
TriOsc padOsc3 => padF;
0.25 => padOsc1.gain; 0.3 => padOsc2.gain; 0.2 => padOsc3.gain;
400.0 => padF.freq; 1.8 => padF.Q;
0.0 => padG.gain;
0.0 => float padGainTarget;
400.0 => float padFiltTarget;
0 => int padLastDeg;
0.0 => float padLfoPhase;

// ============ CLAP ============
Noise clpN => BPF clpBP => ADSR clpEnv => Gain clpG => master;
1200.0 => clpBP.freq; 2.0 => clpBP.Q;
clpEnv.set(0.5::ms, 60::ms, 0.0, 20::ms);
0.0 => clpG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0]] @=> int clpPat[][];

// ============ RISER / FX ============
Noise riserN => BPF riserBP => Gain riserG => master;
500.0 => riserBP.freq; 4.0 => riserBP.Q;
0.0 => riserG.gain;
500.0 => float riserFreqTarget;

// Impact: big low sine hit for drop moments
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
            newScale % 4 => scaleType;
            newSeed % 256 => seed;
            newSeed % 2 => variant;
            seed % progs.cap() => progIdx;
            0 => phraseBar;
            0 => chordIdx;
            progs[progIdx][0] => chordRoot;
            generateMotif();

            // --- TRANSITION TRIGGERS ---
            // Only trigger if not already in a transition
            if(transition == 0 && energy >= 1) {
                if(newEnergy >= 3 && energy < 3) {
                    // Big moment: riser → drop → impact
                    2 => transition;
                    3 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy >= 2 && newEnergy > energy) {
                    // Medium: short riser into drop
                    2 => transition;
                    2 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy == 0) {
                    // Error/breakdown: immediate strip
                    4 => transition;
                    2 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy < energy && energy >= 2) {
                    // Winding down: filter sweep breakdown
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

            // Cancel auto-evolution — real event takes over
            if(autoActive) {
                0 => autoActive;
                0 => autoSection;
                0 => autoSectionBar;
            }

            if(energy >= 2) {
                0.09 => ldDry.gain;
                0.08 => clpG.gain;
            } else {
                0.0 => ldAmpTarget;
                0.0 => clpG.gain;
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
        barsSinceEvent + 1 => barsSinceEvent;

        // Transition bar countdown
        if(transition > 0) {
            transitionBars - 1 => transitionBars;
            if(transitionBars <= 0) {
                // Transition ending — trigger impact if it was a drop
                if(transition == 2) {
                    3 => transition; // switch to impact bar
                    1 => transitionBars;
                } else {
                    0 => transition;
                    0 => riserG.gain;
                }
            }
        }

        // Advance phrase / chord progression
        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) 0 => phraseBar;
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        progs[progIdx][chordIdx] => chordRoot;

        // Energy decay — but trigger auto-evolution instead of silence
        if(barsSinceEvent > 6 && energy > 0 && transition == 0 && !autoActive) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) {
                0.0 => ldAmpTarget;
                0.0 => clpG.gain;
            }
        }

        // Auto-evolution: kick in after sustained idle instead of fading out
        if(barsSinceEvent > 10 && !autoActive && transition == 0) {
            1 => autoActive;
            1 => autoSection;       // start with breakdown
            0 => autoSectionBar;
            2 => energy;            // keep energy alive
            1.0 => masterTarget;
        }

        // Advance auto-evolution sections
        if(autoActive) {
            autoSectionBar + 1 => autoSectionBar;
            1.0 => masterTarget;    // never fade to silence during auto

            if(autoSectionBar >= autoSectionLen[autoSection]) {
                0 => autoSectionBar;
                autoNextSection[autoSection] => autoSection;

                // Section entry logic
                if(autoSection == 1) {
                    // Breakdown: strip to pad + sparse hats
                    1 => energy;
                    0.0 => ldAmpTarget;
                    0.0 => clpG.gain;
                    0.06 => padGainTarget;
                    300.0 => bassFiltTarget;
                } else if(autoSection == 2) {
                    // Ambient: pad only, regenerate motif for freshness
                    1 => energy;
                    0.08 => padGainTarget;
                    1000.0 => padFiltTarget;
                    generateMotif();
                } else if(autoSection == 3) {
                    // Build: riser + hats fill, energy rises
                    2 => energy;
                    2 => transition;
                    4 => transitionBars;
                    0 => transitionStep;
                } else if(autoSection == 4) {
                    // Drop: everything back, impact
                    3 => energy;
                    3 => transition;
                    1 => transitionBars;
                    0.09 => ldDry.gain;
                    0.08 => clpG.gain;
                    0.09 => padGainTarget;
                } else {
                    // Section 0: normal groove, cycle restarts
                    2 => energy;
                    0.09 => ldDry.gain;
                    0.08 => clpG.gain;
                }
            }
        }
    }

    // ---- TRANSITION FX ----
    transitionStep + 1 => transitionStep;

    0 => int kickMuted;
    0 => int hatFill;

    // Auto-evolution section overrides
    if(autoActive) {
        if(autoSection == 1) {
            // Breakdown: kill kick, sparse hats only
            1 => kickMuted;
            200.0 + Math.sin(stepCount * 0.01) * 100.0 => bassFiltTarget;
        } else if(autoSection == 2) {
            // Ambient: no kick, no hats, just pad breathing
            1 => kickMuted;
            0.0 => chG.gain;
        } else if(autoSection == 3) {
            // Build: hats fill in final 2 bars
            if(autoSectionBar >= 2) 1 => hatFill;
        }
        // Section 4 (drop) and 0 (normal) use default behavior
        if(autoSection != 2) 0.07 => chG.gain;
    }

    if(transition == 2) {
        // DROP: kill kick, riser sweeps up, hats do fill in last bar
        1 => kickMuted;
        // Riser noise sweep: freq rises over the transition
        0.07 + transitionStep * 0.0005 => float rGain;
        if(rGain > 0.12) 0.12 => rGain;
        rGain => riserG.gain;
        500.0 + transitionStep * 80.0 => riserFreqTarget;
        if(riserFreqTarget > 12000.0) 12000.0 => riserFreqTarget;
        // Hat fill: every step in last 8 steps of transition
        if(transitionBars <= 1 && s >= 8) 1 => hatFill;
    } else if(transition == 3) {
        // IMPACT: kick comes back HARD, riser cuts, big low hit
        0 => transition;
        0 => riserG.gain;
        // Trigger impact boom
        0.5 => impactG.gain;
        50.0 => impactOsc.freq;
        0.9 => impactOsc.gain;
        // Extra hard kick on beat 1
        if(s == 0) {
            0.0 => kickPh;
            1.0 => kickOsc.gain;
            kickClickEnv.keyOn();
        }
    } else if(transition == 4) {
        // BREAKDOWN: filter everything down, thin out
        1 => kickMuted;
        // Sweep bass filter down
        200.0 => bassFiltTarget;
        400.0 => ldFiltTarget;
        0.0 => ldAmpTarget;
    }

    // ---- KICK (with velocity) ----
    if(!kickMuted && kPat[energy][s]) {
        0.0 => kickPh;
        0.5 + 0.5 * kickVel[s] => float kVel; // range 0.5-1.0
        kVel * 0.8 => kickOsc.gain;
        kVel * 0.3 => kickClick.gain;
        kickClickEnv.keyOn();
    }

    // ---- HATS (with velocity) ----
    if(hatFill) {
        // Fill: rapid-fire hats, crescendo toward end
        (s $ float) / 16.0 => float fillVel;
        0.03 + 0.07 * fillVel => chG.gain;
        chEnv.keyOn();
        if(s % 2 == 0) ohEnv.keyOn();
    } else {
        if(chPat[energy][s]) {
            0.03 + 0.06 * hatVel[s] => chG.gain;
            chEnv.keyOn();
        }
        if(ohPat[energy][s]) {
            0.03 + 0.04 * hatVel[s] => ohG.gain;
            ohEnv.keyOn();
        }
    }

    // ---- CLAP ----
    if(clpPat[energy][s]) clpEnv.keyOn();

    // ---- BASS (follows chord root) ----
    if(transition != 4) {
        -1 => int bDeg;
        if(variant == 0) bPatA[energy][s] => bDeg;
        else bPatB[energy][s] => bDeg;

        if(energy >= 1 && bDeg >= 0) {
            // Offset bass degrees by current chord root
            (bDeg + chordRoot) % 5 => bDeg;
            2 => int bassOct;
            if(bOctUp[energy][s] || Math.random2(0, 6) == 0) 3 => bassOct;
            Std.mtof(note(bDeg, bassOct)) => bassOsc.freq;
            if(bAcc[energy][s]) {
                2000.0 + Math.random2f(0.0, 1500.0) => bassFiltTarget;
            } else {
                600.0 + Math.random2f(0.0, 800.0) => bassFiltTarget;
            }
        }
    }

    // ---- PAD (follows chord progression) ----
    if(energy >= 2 && transition != 4 && s == 0) {
        // Chord: root, 3rd, 5th relative to current chord root
        chordRoot => int pRoot;
        chordRoot + 2 => int pDeg2;
        chordRoot + 4 => int pDeg3;
        Std.mtof(note(pRoot, 4)) => padOsc1.freq;
        Std.mtof(note(pDeg2, 4)) => padOsc2.freq;
        Std.mtof(note(pDeg3, 4)) => padOsc3.freq;
        // Slight detune for width
        padOsc1.freq() * 0.998 => padOsc1.freq;
        padOsc3.freq() * 1.002 => padOsc3.freq;
        0.06 => padGainTarget;
        if(energy >= 3) 0.09 => padGainTarget;
        800.0 + Math.random2f(0.0, 600.0) => padFiltTarget;
    } else if(energy < 2) {
        0.0 => padGainTarget;
    }

    // ---- LEAD (4-bar motif phrase with velocity) ----
    if(energy >= 2 && transition != 4 && motifGenerated) {
        motif[phraseStep % PHRASE_LEN] => int deg;
        if(deg >= 0) {
            // Offset by chord root for harmonic movement
            (deg + chordRoot) % 5 => deg;
            // Bars 3-4 of phrase (steps 32+) go up an octave at energy 3
            4 => int ldOct;
            if(energy >= 3 && phraseStep >= 32) 5 => ldOct;
            Std.mtof(note(deg, ldOct)) => ldOsc1.freq;
            ldOsc1.freq() * 2.0 => ldOsc2.freq; // octave up
            // Velocity: on-beat notes louder, off-beat softer
            phraseStep % 16 => int localStep;
            0.04 => float ldVel;
            if(localStep % 4 == 0) 0.09 => ldVel;      // downbeats: loud
            else if(localStep % 2 == 0) 0.06 => ldVel;  // on-beats: medium
            // Phrase contour: bar 3 (development) is loudest
            if(phraseStep >= 32 && phraseStep < 48) ldVel * 1.2 => ldVel;
            // Bar 4 (resolution) pulls back
            if(phraseStep >= 48) ldVel * 0.75 => ldVel;
            1200.0 + Math.random2f(0.0, 800.0) => ldFiltTarget;
            ldVel => ldAmpTarget;
        }
        phraseStep + 1 => phraseStep;
        if(phraseStep >= PHRASE_LEN) 0 => phraseStep;
    }

    // ---- SUBSTEP ENVELOPE UPDATES ----
    // Swing: pairs of steps share a fixed total duration (2 * stepDur).
    // Even steps get swingAmt of the pair, odd steps get the rest.
    // swingAmt=0.5 → straight, 0.62 → groovy shuffle
    stepDur => dur thisStepDur;
    if(s % 2 == 0) {
        stepDur * 2.0 * swingAmt => thisStepDur;
    } else {
        stepDur * 2.0 * (1.0 - swingAmt) => thisStepDur;
    }
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        // Kick pitch envelope: deeper, rounder, longer tail
        if(kickOsc.gain() > 0.005) {
            38.0 + 80.0 * Math.exp(-kickPh * 8.0) => kickOsc.freq;
            kickOsc.freq() * 4.0 => kickLPF.freq;
            kickOsc.gain() * 0.95 => kickOsc.gain;
            kickPh + 0.08 => kickPh;
        } else {
            0.0 => kickOsc.gain;
        }

        // Impact decay
        if(impactG.gain() > 0.01) {
            impactG.gain() * 0.97 => impactG.gain;
            impactOsc.freq() * 0.998 => impactOsc.freq;
        } else {
            0.0 => impactG.gain;
            0.0 => impactOsc.gain;
        }

        // Riser filter smooth
        riserBP.freq() + (riserFreqTarget - riserBP.freq()) * 0.05 => riserBP.freq;

        // Bass filter slide + decay
        bassF.freq() + (bassFiltTarget - bassF.freq()) * 0.12 => bassF.freq;
        if(bassFiltTarget > 220.0) bassFiltTarget * 0.994 => bassFiltTarget;

        // Lead filter — gentle movement, sine doesn't need aggressive sweep
        ldF.freq() + (ldFiltTarget - ldF.freq()) * 0.03 => ldF.freq;
        if(ldFiltTarget > 1200.0) ldFiltTarget * 0.999 => ldFiltTarget;

        // Lead amplitude envelope — slower attack/release for sine tone
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.05 => ldAmpCurrent;
        ldAmpCurrent => ldDry.gain;
        if(ldAmpTarget > 0.01) ldAmpTarget * 0.988 => ldAmpTarget;

        // Pad filter sweep with LFO modulation
        padLfoPhase + 0.002 => padLfoPhase;
        Math.sin(padLfoPhase) * 200.0 => float padLfoMod;
        padF.freq() + ((padFiltTarget + padLfoMod) - padF.freq()) * 0.015 => padF.freq;
        if(padFiltTarget > 300.0) padFiltTarget * 0.9997 => padFiltTarget;
        padG.gain() + (padGainTarget - padG.gain()) * 0.01 => padG.gain;
        if(transition == 4) 0.0 => padGainTarget;

        // Master gain smooth
        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain => master.gain;

        thisStepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
