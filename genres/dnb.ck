// dnb.ck - Beatpilot Drum & Bass Engine
// 174 BPM, breakbeat patterns, heavy sub bass, atmospheric leads

// ============ CLOCK ============
174.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;
4 => int SUBSTEPS;
0.58 => float swingAmt; // subtle shuffle — DnB is less swung than techno

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
[[0, 3, 4, 2], [0, 4, 3, 1], [0, 3, 5, 2], [0, 4, 1, 3], [0, 5, 3, 1]] @=> int progs[][];
0 => int progIdx;
0 => int chordIdx;
0 => int chordRoot;
0 => int phraseBar;

// ============ LEAD MOTIF (4-bar phrase) ============
64 => int PHRASE_LEN;
int motif[64];
0 => int motifGenerated;
0 => int phraseStep;

fun void generateMotif() {
    seed => int s;
    for(0 => int i; i < PHRASE_LEN; i++) -1 => motif[i];

    // DnB lead: longer sustained notes, fewer hits, more space for delay
    int fig[4];
    0 => fig[0];
    (s % 3 + 1) => fig[1];
    (s % 2 + 2) => fig[2];
    ((s / 2) % 2) => fig[3];

    // Bar 1: sparse call — 3 notes with space
    fig[0] => motif[0];
    fig[1] => motif[6];
    fig[2] => motif[12];

    // Bar 2: response — shifted rhythm
    fig[0] + 2 => motif[18];
    fig[1] + 1 => motif[24];
    fig[3] => motif[28];

    // Bar 3: climax — more notes, higher
    fig[2] + 2 => motif[32];
    fig[1] + 2 => motif[36];
    fig[0] + 3 => motif[38];
    fig[2] => motif[42];
    fig[1] => motif[46];

    // Bar 4: resolve — descend to root
    fig[2] => motif[48];
    fig[1] => motif[54];
    0 => motif[60];

    0 => phraseStep;
    1 => motifGenerated;
}

// ============ TRANSITION STATE ============
0 => int transition;
0 => int transitionBars;
0 => int transitionStep;

// ============ AUTO-EVOLUTION ============
0 => int autoSection;
0 => int autoSectionBar;
0 => int autoActive;
[0, 8, 6, 4, 1] @=> int autoSectionLen[];
[1, 2, 3, 4, 0] @=> int autoNextSection[];

// ============ MASTER BUS + REVERB ============
Gain master => Gain dryOut => dac;
0.0 => master.gain;
// Reverb: 4-tap diffusion
master => DelayL rv1 => Gain rvFb1 => LPF rvF1 => Gain rvMix => dac;
master => DelayL rv2 => Gain rvFb2 => LPF rvF2 => rvMix;
master => DelayL rv3 => Gain rvFb3 => LPF rvF3 => rvMix;
master => DelayL rv4 => Gain rvFb4 => LPF rvF4 => rvMix;
rvFb1 => rv3; rvFb2 => rv4; rvFb3 => rv1; rvFb4 => rv2;
0.12::second => rv1.max; 0.1073::second => rv1.delay;
0.16::second => rv2.max; 0.1423::second => rv2.delay;
0.2::second => rv3.max; 0.1847::second => rv3.delay;
0.28::second => rv4.max; 0.2531::second => rv4.delay;
0.35 => rvFb1.gain; 0.33 => rvFb2.gain; 0.31 => rvFb3.gain; 0.30 => rvFb4.gain;
3000.0 => rvF1.freq; 2800.0 => rvF2.freq; 2500.0 => rvF3.freq; 2200.0 => rvF4.freq;
0.18 => rvMix.gain;
0.82 => dryOut.gain;

// ============ SCALES ============
[[0,2,4,7,9], [0,3,5,7,10], [0,2,3,5,7,8,11], [0,2,3,5,7,8,10]] @=> int scales[][];

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    if(degree < 0) return 0;
    return key + octave * 12 + scl[degree % scl.cap()] + (degree / scl.cap()) * 12;
}

// ============ VELOCITY MAPS ============
// Breakbeat ghost note dynamics
[1.0, 0.0, 0.5, 0.0, 1.0, 0.0, 0.6, 0.3, 0.9, 0.0, 0.7, 0.3, 1.0, 0.0, 0.5, 0.4] @=> float snVel[];
[1.0, 0.3, 0.6, 0.3, 0.9, 0.3, 0.7, 0.4, 1.0, 0.3, 0.6, 0.35, 0.9, 0.35, 0.7, 0.5] @=> float hatVel[];
[1.0, 0.0, 0.0, 0.0, 0.85, 0.0, 0.9, 0.0, 0.95, 0.0, 0.85, 0.0, 0.8, 0.7, 0.0, 0.0] @=> float kickVel[];

// ============ KICK ============
SinOsc kickOsc => LPF kickLPF => Gain kickG => master;
0.0 => kickOsc.gain;
300.0 => kickLPF.freq;
0.40 => kickG.gain;
0.0 => float kickPh;
Noise kickClick => BPF kickClickBP => ADSR kickClickEnv => kickG;
3500.0 => kickClickBP.freq; 1.5 => kickClickBP.Q;
kickClickEnv.set(0.2::ms, 8::ms, 0.0, 3::ms);
0.3 => kickClick.gain;

// More complex breakbeat patterns with ghost kicks
[[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0],
 [1,0,0,0,0,0,1,0,0,0,1,0,0,0,0,0],
 [1,0,0,0,0,0,1,0,0,0,1,0,0,1,0,0]] @=> int kPatA[][];

// Variant B: more syncopated
[[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,1,0,0,1,0,0,0,0],
 [1,0,0,1,0,0,0,0,1,0,0,1,0,0,1,0]] @=> int kPatB[][];

// ============ SNARE ============
Noise snN => BPF snBP => ADSR snEnv => Gain snG => master;
1800.0 => snBP.freq; 1.5 => snBP.Q;
snEnv.set(0.3::ms, 80::ms, 0.0, 30::ms);
0.0 => snG.gain;

// Main snare patterns + ghost snare patterns
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,1,0,0,1,0,0,0]] @=> int snPatA[][];

// Variant B: busier breaks
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,1,0,0,0,0,1,0,0,1],
 [0,0,1,0,1,0,0,1,0,0,1,0,1,0,0,1]] @=> int snPatB[][];

// Ghost snare hits (quieter, for texture)
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,0,0,0,0,1,0,0,0,1,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,1,0,1]] @=> int snGhost[][];

// ============ HATS ============
Noise chN => HPF chHP => ADSR chEnv => Gain chG => master;
9000.0 => chHP.freq;
chEnv.set(0.3::ms, 18::ms, 0.0, 5::ms);
0.05 => chG.gain;

// Open hat
Noise ohN => BPF ohBP => ADSR ohEnv => Gain ohG => master;
10000.0 => ohBP.freq; 1.5 => ohBP.Q;
ohEnv.set(1::ms, 120::ms, 0.03, 80::ms);
0.04 => ohG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0],
 [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0]] @=> int chPat[][];

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1],
 [0,0,0,0,0,0,0,1,0,0,0,1,0,0,1,0]] @=> int ohPat[][];

// ============ SUB BASS (follows chord root) ============
SinOsc subOsc => Gain subG => master;
0.0 => subG.gain;
0.0 => float subAmpTarget;
0.0 => float subAmpCurrent;

[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1,-1,-1, 0,-1,-1,-1,-1,-1, 0,-1],
 [ 0,-1,-1, 0,-1,-1,-1,-1, 0,-1,-1,-1, 0,-1, 0,-1]] @=> int subPat[][];

// ============ REESE BASS (follows chord root, detuned saws) ============
SawOsc reese1 => LPF reeseFilt => Gain reeseG => master;
SawOsc reese2 => reeseFilt;
0.4 => reese1.gain; 0.4 => reese2.gain;
800.0 => reeseFilt.freq; 3.0 => reeseFilt.Q;
0.0 => reeseG.gain;
800.0 => float reeseFiltTarget;

// ============ PAD (detuned pairs for warmth) ============
TriOsc pad1a => LPF padFilt => Gain padG => master;
TriOsc pad1b => padFilt;
TriOsc pad2a => padFilt;
TriOsc pad2b => padFilt;
TriOsc pad3a => padFilt;
TriOsc pad3b => padFilt;
0.15 => pad1a.gain; 0.15 => pad1b.gain;
0.15 => pad2a.gain; 0.15 => pad2b.gain;
0.12 => pad3a.gain; 0.12 => pad3b.gain;
1400.0 => padFilt.freq; 0.8 => padFilt.Q;
0.0 => padG.gain;
0.0 => float padAmpTarget;
0.0 => float padAmpCurrent;
1400.0 => float padFiltTarget;
0.0 => float padLfoPhase;

// ============ LEAD (FM synthesis — glassy, metallic) ============
// Carrier + modulator with drifting mod depth for evolving timbre
SinOsc ldMod => SinOsc ldCarr => LPF ldFilt => Gain ldDry => master;
2 => ldCarr.sync; // FM mode
0.5 => ldCarr.gain;
80.0 => ldMod.gain; // mod depth in Hz — controls metallicness
2400.0 => ldFilt.freq; 1.2 => ldFilt.Q;
0.0 => ldDry.gain;
2400.0 => float ldFiltTarget;
0.0 => float ldAmpTarget;
0.0 => float ldAmpCurrent;
80.0 => float ldModTarget; // target mod depth — varies per note

// Lead delay: dotted-eighth for DnB rhythm
ldDry => DelayL ldDly => Gain ldDlyFb => LPF ldDlyF => master;
ldDlyFb => ldDly;
(stepDur * 3) => ldDly.max => ldDly.delay;
0.40 => ldDlyFb.gain;
0.04 => ldDly.gain;
2800.0 => ldDlyF.freq;

// ============ STAB (chord hits, with reverb tail) ============
SawOsc stab1 => LPF stabFilt => ADSR stabEnv => Gain stabG => master;
SawOsc stab2 => stabFilt;
SawOsc stab3 => stabFilt;
0.2 => stab1.gain; 0.2 => stab2.gain; 0.2 => stab3.gain;
2500.0 => stabFilt.freq; 2.0 => stabFilt.Q;
stabEnv.set(1::ms, 120::ms, 0.0, 60::ms);
0.0 => stabG.gain;

// ============ RISER / FX ============
Noise riserN => BPF riserBP => Gain riserG => master;
500.0 => riserBP.freq; 4.0 => riserBP.Q;
0.0 => riserG.gain;
500.0 => float riserFreqTarget;

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

            if(transition == 0 && energy >= 1) {
                if(newEnergy >= 3 && energy < 3) {
                    2 => transition; 3 => transitionBars; 0 => transitionStep;
                } else if(newEnergy >= 2 && newEnergy > energy) {
                    2 => transition; 2 => transitionBars; 0 => transitionStep;
                } else if(newEnergy == 0) {
                    4 => transition; 2 => transitionBars; 0 => transitionStep;
                }
            }

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
                0.10 => snG.gain;
                0.10 => subG.gain;
                0.05 => ldDry.gain;
            }
            if(energy >= 2) {
                0.06 => reeseG.gain;
                0.05 => padAmpTarget;
                0.06 => stabG.gain;
            } else {
                0.0 => reeseG.gain;
                0.0 => padAmpTarget;
                0.0 => stabG.gain;
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

        // Transition bar countdown
        if(transition > 0) {
            transitionBars - 1 => transitionBars;
            if(transitionBars <= 0) {
                if(transition == 2) { 3 => transition; 1 => transitionBars; }
                else { 0 => transition; 0.0 => riserG.gain; }
            }
        }

        // Advance chord progression
        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) 0 => phraseBar;
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        progs[progIdx][chordIdx] => chordRoot;

        // Energy decay
        if(barsSinceEvent > 6 && energy > 0 && transition == 0 && !autoActive) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) {
                0.0 => reeseG.gain;
                0.0 => padAmpTarget;
                0.0 => stabG.gain;
            }
            if(energy < 1) {
                0.0 => snG.gain;
                0.0 => subG.gain;
                0.0 => ldAmpTarget;
            }
        }

        // Auto-evolution instead of silence
        if(barsSinceEvent > 10 && !autoActive && transition == 0) {
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
                    // Breakdown: strip to halftime, pad + sub only
                    1 => energy;
                    0.0 => reeseG.gain;
                    0.0 => stabG.gain;
                    0.0 => ldAmpTarget;
                    0.04 => padAmpTarget;
                    0.08 => subG.gain;
                    0.08 => snG.gain;
                } else if(autoSection == 2) {
                    // Build: reese comes in, hats intensify
                    2 => energy;
                    0.05 => reeseG.gain;
                    0.05 => padAmpTarget;
                    0.10 => snG.gain;
                    generateMotif();
                } else if(autoSection == 3) {
                    // Riser into drop
                    3 => energy;
                    2 => transition;
                    4 => transitionBars;
                    0 => transitionStep;
                } else if(autoSection == 4) {
                    // Drop: full energy slam
                    3 => energy;
                    3 => transition;
                    1 => transitionBars;
                    0.06 => reeseG.gain;
                    0.06 => stabG.gain;
                    0.10 => snG.gain;
                    0.05 => padAmpTarget;
                } else {
                    2 => energy;
                    0.10 => snG.gain;
                    0.06 => reeseG.gain;
                }
            }
        }
    }

    // ---- TRANSITION FX ----
    transitionStep + 1 => transitionStep;
    0 => int kickMuted;
    0 => int hatFill;

    // Auto-evolution overrides
    if(autoActive) {
        if(autoSection == 1) {
            // Breakdown: halftime feel — only kick on 1, snare on 9
            if(s != 0) 1 => kickMuted;
        }
        if(autoSection != 1) 0.05 => chG.gain;
    }

    if(transition == 2) {
        1 => kickMuted;
        0.07 + transitionStep * 0.0005 => float rGain;
        if(rGain > 0.12) 0.12 => rGain;
        rGain => riserG.gain;
        500.0 + transitionStep * 80.0 => riserFreqTarget;
        if(riserFreqTarget > 12000.0) 12000.0 => riserFreqTarget;
        if(transitionBars <= 1 && s >= 8) 1 => hatFill;
    } else if(transition == 3) {
        0 => transition; 0.0 => riserG.gain;
        0.5 => impactG.gain; 50.0 => impactOsc.freq; 0.9 => impactOsc.gain;
        if(s == 0) { 0.0 => kickPh; 1.0 => kickOsc.gain; kickClickEnv.keyOn(); }
    } else if(transition == 4) {
        1 => kickMuted;
        0.0 => padAmpTarget;
        200.0 => reeseFiltTarget;
    }

    // ---- KICK (with velocity) ----
    if(!kickMuted) {
        0 => int kHit;
        if(variant == 0 && kPatA[energy][s]) 1 => kHit;
        if(variant == 1 && kPatB[energy][s]) 1 => kHit;
        if(kHit) {
            0.0 => kickPh;
            0.5 + 0.5 * kickVel[s] => float kVel;
            kVel * 0.8 => kickOsc.gain;
            kVel * 0.3 => kickClick.gain;
            kickClickEnv.keyOn();
        }
    }

    // ---- SNARE (main + ghost with velocity) ----
    0 => int snHit;
    if(variant == 0 && snPatA[energy][s]) 1 => snHit;
    if(variant == 1 && snPatB[energy][s]) 1 => snHit;
    if(snHit) {
        0.08 + 0.04 * snVel[s] => snG.gain;
        snEnv.keyOn();
    } else if(snGhost[energy][s]) {
        // Ghost snare: much quieter
        0.03 => snG.gain;
        snEnv.keyOn();
    }

    // ---- HATS (with velocity) ----
    if(hatFill) {
        (s $ float) / 16.0 => float fillVel;
        0.03 + 0.05 * fillVel => chG.gain;
        chEnv.keyOn();
        if(s % 2 == 0) ohEnv.keyOn();
    } else {
        if(chPat[energy][s]) {
            0.02 + 0.05 * hatVel[s] => chG.gain;
            chEnv.keyOn();
        }
        if(ohPat[energy][s]) {
            0.02 + 0.04 * hatVel[s] => ohG.gain;
            ohEnv.keyOn();
        }
    }

    // ---- SUB BASS (follows chord root) ----
    if(energy >= 1 && subPat[energy][s] >= 0) {
        (subPat[energy][s] + chordRoot) % 5 => int subDeg;
        Std.mtof(note(subDeg, 1)) => subOsc.freq;
        0.15 => subAmpTarget;
    }

    // ---- REESE (follows chord root) ----
    if(energy >= 2 && s % 8 == 0) {
        Std.mtof(note(chordRoot, 2)) => reese1.freq;
        reese1.freq() * 1.008 => reese2.freq;
        1200.0 + Math.random2f(0.0, 800.0) => reeseFiltTarget;
    }

    // ---- PAD (detuned, follows progression) ----
    if(energy >= 2 && s == 0 && phraseBar % 4 == 0) {
        Std.mtof(note(chordRoot, 3)) => float p1;
        Std.mtof(note(chordRoot + 2, 3)) => float p2;
        Std.mtof(note(chordRoot + 4, 3)) => float p3;
        p1 * 0.997 => pad1a.freq; p1 * 1.003 => pad1b.freq;
        p2 * 0.997 => pad2a.freq; p2 * 1.003 => pad2b.freq;
        p3 * 0.998 => pad3a.freq; p3 * 1.002 => pad3b.freq;
        0.05 => padAmpTarget;
        1400.0 + Math.random2f(0.0, 400.0) => padFiltTarget;
    }

    // ---- LEAD (4-bar motif with velocity) ----
    if(energy >= 1 && transition != 4 && motifGenerated) {
        motif[phraseStep % PHRASE_LEN] => int deg;
        if(deg >= 0) {
            (deg + chordRoot) % 5 => deg;
            4 => int ldOct;
            if(energy >= 3 && phraseStep >= 32) 5 => ldOct;
            Std.mtof(note(deg, ldOct)) => ldCarr.freq;
            // Mod ratio 3:2 = glassy bell, 2:1 = brighter, 5:3 = more metallic
            ldCarr.freq() * 1.5 => ldMod.freq;
            // Vary mod depth per note for timbral movement
            60.0 + Math.random2f(0.0, 80.0) => ldModTarget;
            // Velocity: phrase contour
            phraseStep % 16 => int localStep;
            0.035 => float ldVel;
            if(localStep % 4 == 0) 0.06 => ldVel;
            else if(localStep % 2 == 0) 0.045 => ldVel;
            if(phraseStep >= 32 && phraseStep < 48) ldVel * 1.2 => ldVel;
            if(phraseStep >= 48) ldVel * 0.7 => ldVel;
            2400.0 + Math.random2f(0.0, 600.0) => ldFiltTarget;
            ldVel => ldAmpTarget;
        }
        phraseStep + 1 => phraseStep;
        if(phraseStep >= PHRASE_LEN) 0 => phraseStep;
    }

    // ---- STAB (chord hits, follows progression) ----
    if(energy >= 2 && transition == 0) {
        if(s == 2 || s == 10 || (energy >= 3 && s == 6)) {
            Std.mtof(note(chordRoot, 4)) => stab1.freq;
            Std.mtof(note(chordRoot + 2, 4)) => stab2.freq;
            Std.mtof(note(chordRoot + 4, 4)) => stab3.freq;
            2500.0 => stabFilt.freq;
            stabEnv.keyOn();
        }
    }

    // ---- SWING TIMING ----
    stepDur => dur thisStepDur;
    if(s % 2 == 0) {
        stepDur * 2.0 * swingAmt => thisStepDur;
    } else {
        stepDur * 2.0 * (1.0 - swingAmt) => thisStepDur;
    }

    // ---- SUBSTEP UPDATES ----
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        // Kick envelope
        if(kickOsc.gain() > 0.005) {
            38.0 + 80.0 * Math.exp(-kickPh * 8.0) => kickOsc.freq;
            kickOsc.freq() * 4.0 => kickLPF.freq;
            kickOsc.gain() * 0.95 => kickOsc.gain;
            kickPh + 0.08 => kickPh;
        } else { 0.0 => kickOsc.gain; }

        // Impact
        if(impactG.gain() > 0.01) {
            impactG.gain() * 0.97 => impactG.gain;
            impactOsc.freq() * 0.998 => impactOsc.freq;
        } else { 0.0 => impactG.gain; 0.0 => impactOsc.gain; }

        // Riser
        riserBP.freq() + (riserFreqTarget - riserBP.freq()) * 0.05 => riserBP.freq;

        // Sub bass
        subAmpCurrent + (subAmpTarget - subAmpCurrent) * 0.05 => subAmpCurrent;
        subAmpCurrent => subG.gain;
        if(subAmpTarget > 0.01) subAmpTarget * 0.995 => subAmpTarget;

        // Reese filter
        reeseFilt.freq() + (reeseFiltTarget - reeseFilt.freq()) * 0.08 => reeseFilt.freq;
        if(reeseFiltTarget > 300.0) reeseFiltTarget * 0.996 => reeseFiltTarget;

        // Pad: breathing + filter LFO
        padLfoPhase + 0.001 => padLfoPhase;
        padAmpCurrent + (padAmpTarget - padAmpCurrent) * 0.006 => padAmpCurrent;
        padAmpCurrent => padG.gain;
        if(padAmpTarget > 0.003) padAmpTarget * 0.9998 => padAmpTarget;
        Math.sin(padLfoPhase) * 250.0 => float padLfoMod;
        padFilt.freq() + ((padFiltTarget + padLfoMod) - padFilt.freq()) * 0.01 => padFilt.freq;
        if(padFiltTarget > 500.0) padFiltTarget * 0.9999 => padFiltTarget;

        // Pad detune drift
        pad1b.freq() * (1.0 + 0.0002 * Math.sin(stepCount * 0.00011)) => pad1b.freq;
        pad2b.freq() * (1.0 + 0.0002 * Math.sin(stepCount * 0.00009)) => pad2b.freq;
        pad3b.freq() * (1.0 + 0.0002 * Math.sin(stepCount * 0.00013)) => pad3b.freq;

        // Lead — FM envelope: mod depth drifts for evolving timbre
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.04 => ldAmpCurrent;
        ldAmpCurrent => ldDry.gain;
        if(ldAmpTarget > 0.003) ldAmpTarget * 0.990 => ldAmpTarget;
        ldFilt.freq() + (ldFiltTarget - ldFilt.freq()) * 0.03 => ldFilt.freq;
        if(ldFiltTarget > 800.0) ldFiltTarget * 0.998 => ldFiltTarget;
        // FM mod depth decays toward target, with slow LFO drift
        ldMod.gain() + (ldModTarget - ldMod.gain()) * 0.01 => ldMod.gain;
        if(ldModTarget > 30.0) ldModTarget * 0.9995 => ldModTarget;

        // Stab filter decay
        if(stabFilt.freq() > 800.0) stabFilt.freq() * 0.998 => stabFilt.freq;

        // Master
        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain => master.gain;

        thisStepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
