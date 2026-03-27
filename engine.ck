// engine.ck - Beatpilot Techno Engine
// A continuous techno groove that evolves based on Claude hook events.
// Reads state from /tmp/beatpilot-state (written by hook.sh).
// Energy (0-3) controls which layers are active and pattern intensity.

// ============ CLOCK ============
128.0 => float BPM;
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
0 => int variant; // 0 or 1, selected by seed

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
SinOsc kickOsc => Gain kickG => master;
0.0 => kickOsc.gain;
0.40 => kickG.gain;
0.0 => float kickPh;

[[1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,1,0],
 [1,0,1,0,1,0,0,0,1,0,1,0,1,0,0,1]] @=> int kPat[][];

// ============ CLOSED HAT ============
Noise chN => HPF chHP => ADSR chEnv => Gain chG => master;
8000.0 => chHP.freq;
chEnv.set(0.3::ms, 22::ms, 0.0, 5::ms);
0.07 => chG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0],
 [1,0,1,1,1,0,1,0,1,0,1,1,1,0,1,1]] @=> int chPat[][];

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
// Two pattern banks (selected by seed) x 4 energy levels = 8 patterns
// Uses octave jumps, syncopation, rests for interest
SawOsc bassOsc => LPF bassF => Gain bassG => master;
0.7 => bassOsc.gain;
200.0 => bassF.freq; 9.0 => bassF.Q;
0.15 => bassG.gain;
200.0 => float bassFiltTarget;

// Bank A: degree patterns (-1 = rest)
[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1,-1,-1, 0,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1, 0,-1,-1, 3,-1, 0,-1,-1,-1,-1, 4, 0,-1],
 [ 0,-1, 5,-1, 0,-1,-1, 3, 0,-1,-1, 7, 0,-1, 5,-1]] @=> int bPatA[][];

// Bank B: different rhythms and notes
[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1, 0,-1,-1,-1,-1,-1, 0,-1,-1,-1],
 [ 0,-1, 0,-1,-1, 4,-1,-1,-1, 0,-1,-1, 3,-1,-1, 0],
 [ 0, 5,-1, 0,-1, 3,-1, 7,-1, 0,-1, 5, 0,-1, 3,-1]] @=> int bPatB[][];

// Accent patterns (per energy, shared across banks)
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],
 [1,0,0,1,0,0,1,0,1,0,0,0,0,1,0,0],
 [1,0,1,0,1,0,0,1,1,0,0,1,0,1,0,1]] @=> int bAcc[][];

// Octave map: some steps jump up an octave for acid effect
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0],
 [0,0,1,0,0,0,0,0,0,0,0,1,0,0,1,0]] @=> int bOctUp[][];

// ============ LEAD ============
// Warmer timbre: TriOsc, lower Q, wider intervals, lots of space
TriOsc ldOsc1 => LPF ldF => Gain ldG => master;
TriOsc ldOsc2 => ldF;
0.5 => ldOsc1.gain; 0.5 => ldOsc2.gain;
600.0 => ldF.freq; 3.0 => ldF.Q;
0.0 => ldG.gain;
600.0 => float ldFiltTarget;
0.0 => float ldAmpTarget;
0.0 => float ldAmpCurrent;

// Bank A: sparse, wide intervals (4ths, 5ths, octaves)
[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 4,-1,-1,-1,-1,-1,-1,-1, 0,-1,-1,-1,-1,-1,-1,-1],
 [-1, 4,-1,-1, 0,-1,-1, 7,-1,-1, 4,-1,-1,-1,-1,-1]] @=> int lPatA[][];

// Bank B: different rhythm, complementary intervals
[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [-1,-1,-1,-1, 7,-1,-1,-1,-1,-1,-1,-1, 5,-1,-1,-1],
 [ 7,-1,-1,-1,-1, 5,-1,-1,-1,-1, 9,-1,-1, 7,-1,-1]] @=> int lPatB[][];

// Lead octave: some notes jump up for sparkle
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0]] @=> int lOctUp[][];

// ============ CLAP ============
Noise clpN => BPF clpBP => ADSR clpEnv => Gain clpG => master;
1200.0 => clpBP.freq; 2.0 => clpBP.Q;
clpEnv.set(0.5::ms, 60::ms, 0.0, 20::ms);
0.0 => clpG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0]] @=> int clpPat[][];

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
            newEnergy => energy;
            newKey % 12 => key;
            newScale % 4 => scaleType;
            newSeed % 256 => seed;
            newSeed % 2 => variant;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;

            // Bring master up
            1.0 => masterTarget;

            // Activate layers based on energy
            if(energy >= 2) {
                0.09 => ldG.gain;
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
    // Seed-based rotation for percussion variation
    seed % 3 => int rot;

    // ---- BAR BOUNDARY ----
    if(s == 0) {
        readState();
        barsSinceEvent + 1 => barsSinceEvent;

        // Energy decay
        if(barsSinceEvent > 6 && energy > 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) {
                0.0 => ldAmpTarget;
                0.0 => clpG.gain;
            }
        }
        if(barsSinceEvent > 14) 0.0 => masterTarget;
    }

    // ---- KICK ----
    if(kPat[energy][s]) {
        0.0 => kickPh;
        0.9 => kickOsc.gain;
    }

    // ---- HATS (rotated by seed) ----
    (s + rot) % 16 => int sRot;
    if(chPat[energy][sRot]) chEnv.keyOn();
    if(ohPat[energy][sRot]) ohEnv.keyOn();

    // ---- CLAP ----
    if(clpPat[energy][s]) clpEnv.keyOn();

    // ---- BASS (bank selected by variant) ----
    (s + rot) % 16 => int bStep;
    -1 => int bDeg;
    if(variant == 0) bPatA[energy][bStep] => bDeg;
    else bPatB[energy][bStep] => bDeg;

    if(energy >= 1 && bDeg >= 0) {
        2 => int bassOct;
        if(bOctUp[energy][bStep]) 3 => bassOct;
        Std.mtof(note(bDeg, bassOct)) => bassOsc.freq;
        if(bAcc[energy][bStep]) {
            2400.0 + seed * 5.0 => bassFiltTarget;
        } else {
            800.0 + seed * 3.0 => bassFiltTarget;
        }
    }

    // ---- LEAD (bank selected by variant, wide intervals) ----
    -1 => int lDeg;
    if(variant == 0) lPatA[energy][s] => lDeg;
    else lPatB[energy][s] => lDeg;

    if(energy >= 2 && lDeg >= 0) {
        5 => int ldOct;
        if(lOctUp[energy][s]) 6 => ldOct;
        Std.mtof(note(lDeg, ldOct)) => ldOsc1.freq;
        ldOsc1.freq() * 1.003 => ldOsc2.freq;
        1800.0 + seed * 3.0 => ldFiltTarget;
        0.09 => ldAmpTarget;
    }

    // ---- SUBSTEP ENVELOPE UPDATES ----
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        // Kick pitch envelope
        if(kickOsc.gain() > 0.01) {
            42.0 + 140.0 * Math.exp(-kickPh * 14.0) => kickOsc.freq;
            kickOsc.gain() * 0.92 => kickOsc.gain;
            kickPh + 0.1 => kickPh;
        } else {
            0.0 => kickOsc.gain;
        }

        // Bass filter slide + decay
        bassF.freq() + (bassFiltTarget - bassF.freq()) * 0.12 => bassF.freq;
        if(bassFiltTarget > 220.0) bassFiltTarget * 0.994 => bassFiltTarget;

        // Lead filter decay (gentler than before)
        ldF.freq() + (ldFiltTarget - ldF.freq()) * 0.06 => ldF.freq;
        if(ldFiltTarget > 400.0) ldFiltTarget * 0.996 => ldFiltTarget;

        // Lead amplitude envelope (smooth on/off)
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.08 => ldAmpCurrent;
        ldAmpCurrent => ldG.gain;
        // Decay lead amp between notes
        if(ldAmpTarget > 0.01) ldAmpTarget * 0.992 => ldAmpTarget;

        // Master gain smooth
        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain => master.gain;

        stepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
