// engine.ck - Beatpilot Techno Engine
// A continuous techno groove that evolves based on Claude hook events.
// Reads state from /tmp/beatpilot-state (written by hook.sh).
// Energy (0-3) controls which layers are active and pattern intensity.
// Transitions: drops, risers, fills, and breakdowns triggered by events.

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
0 => int variant;

// ============ TRANSITION STATE ============
// 0=none, 1=riser (building), 2=drop (kick out, tension), 3=impact (kick back hard)
0 => int transition;
0 => int transitionBars;   // bars remaining in current transition
0 => int transitionStep;   // steps into transition
0 => int lastTransitionTs; // prevent overlapping transitions

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
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,1,0]] @=> int kPat[][];

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
TriOsc ldOsc1 => LPF ldF => Gain ldG => master;
TriOsc ldOsc2 => ldF;
0.4 => ldOsc1.gain; 0.4 => ldOsc2.gain;
600.0 => ldF.freq; 2.5 => ldF.Q;
0.0 => ldG.gain;
600.0 => float ldFiltTarget;
0.0 => float ldAmpTarget;
0.0 => float ldAmpCurrent;
-1 => int lastLeadDeg;

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

        // Energy decay
        if(barsSinceEvent > 6 && energy > 0 && transition == 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) {
                0.0 => ldAmpTarget;
                0.0 => clpG.gain;
            }
        }
        if(barsSinceEvent > 14) 0.0 => masterTarget;
    }

    // ---- TRANSITION FX ----
    transitionStep + 1 => transitionStep;

    0 => int kickMuted;
    0 => int hatFill;

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
        }
    } else if(transition == 4) {
        // BREAKDOWN: filter everything down, thin out
        1 => kickMuted;
        // Sweep bass filter down
        200.0 => bassFiltTarget;
        400.0 => ldFiltTarget;
        0.0 => ldAmpTarget;
    }

    // ---- KICK ----
    if(!kickMuted && kPat[energy][s]) {
        0.0 => kickPh;
        0.9 => kickOsc.gain;
    }

    // ---- HATS ----
    if(hatFill) {
        // Fill: rapid-fire hats every step
        chEnv.keyOn();
        if(s % 2 == 0) ohEnv.keyOn();
    } else {
        if(chPat[energy][s]) chEnv.keyOn();
        if(ohPat[energy][s]) ohEnv.keyOn();
    }

    // ---- CLAP ----
    if(clpPat[energy][s]) clpEnv.keyOn();

    // ---- BASS ----
    if(transition != 4) {
        -1 => int bDeg;
        if(variant == 0) bPatA[energy][s] => bDeg;
        else bPatB[energy][s] => bDeg;

        if(energy >= 1 && bDeg >= 0) {
            if(Math.random2(0, 4) == 0) Math.random2(0, 4) => bDeg;
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

    // ---- LEAD (probabilistic) ----
    if(energy >= 2 && transition != 4) {
        Math.random2(0, 99) => int roll;
        if(((energy == 2 && roll < 12) || (energy == 3 && roll < 25)) && ldAmpTarget < 0.02) {
            Math.random2(0, 4) => int deg;
            if(deg == lastLeadDeg) (deg + Math.random2(1, 3)) % 5 => deg;
            deg => lastLeadDeg;
            4 + (Math.random2(0, 3) == 0) => int ldOct;
            Std.mtof(note(deg, ldOct)) => ldOsc1.freq;
            ldOsc1.freq() * 1.003 => ldOsc2.freq;
            1200.0 + Math.random2f(0.0, 1200.0) => ldFiltTarget;
            0.08 => ldAmpTarget;
        }
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

        // Lead filter decay
        ldF.freq() + (ldFiltTarget - ldF.freq()) * 0.06 => ldF.freq;
        if(ldFiltTarget > 400.0) ldFiltTarget * 0.996 => ldFiltTarget;

        // Lead amplitude envelope
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.08 => ldAmpCurrent;
        ldAmpCurrent => ldG.gain;
        if(ldAmpTarget > 0.01) ldAmpTarget * 0.992 => ldAmpTarget;

        // Master gain smooth
        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain => master.gain;

        stepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
