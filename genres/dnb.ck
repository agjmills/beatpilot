// dnb.ck - Beatpilot Drum & Bass Engine
// 174 BPM, breakbeat patterns, heavy sub bass, atmospheric leads

// ============ CLOCK ============
174.0 => float BPM;
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

0 => int transition;
0 => int transitionBars;
0 => int transitionStep;

Gain master => dac;
0.0 => master.gain;

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
0.40 => kickG.gain;
0.0 => float kickPh;
Noise kickClick => BPF kickClickBP => ADSR kickClickEnv => kickG;
3500.0 => kickClickBP.freq; 1.5 => kickClickBP.Q;
kickClickEnv.set(0.2::ms, 8::ms, 0.0, 3::ms);
0.3 => kickClick.gain;

// Breakbeat: kick on 1, ghost on the &-of-2, kick on 3-e
[[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0],
 [1,0,0,0,0,0,1,0,0,0,1,0,0,0,0,0],
 [1,0,0,0,0,0,1,0,0,0,1,0,0,1,0,0]] @=> int kPat[][];

// ============ SNARE ============
Noise snN => BPF snBP => ADSR snEnv => Gain snG => master;
1800.0 => snBP.freq; 1.5 => snBP.Q;
snEnv.set(0.3::ms, 80::ms, 0.0, 30::ms);
0.0 => snG.gain;

// Snare on 2 and 4, with ghost notes at higher energy
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,1,0,0,1,0,0,0]] @=> int snPat[][];

// ============ HATS ============
Noise chN => HPF chHP => ADSR chEnv => Gain chG => master;
9000.0 => chHP.freq;
chEnv.set(0.3::ms, 18::ms, 0.0, 5::ms);
0.05 => chG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0],
 [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0]] @=> int chPat[][];

// ============ SUB BASS ============
SinOsc subOsc => Gain subG => master;
0.0 => subG.gain;

[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1,-1,-1, 0,-1,-1,-1,-1,-1, 0,-1],
 [ 0,-1,-1, 0,-1,-1,-1,-1, 0,-1,-1,-1, 0,-1, 0,-1]] @=> int subPat[][];

0.0 => float subAmpTarget;
0.0 => float subAmpCurrent;

// ============ REESE BASS ============
SawOsc reese1 => LPF reeseFilt => Gain reeseG => master;
SawOsc reese2 => reeseFilt;
0.4 => reese1.gain; 0.4 => reese2.gain;
800.0 => reeseFilt.freq; 3.0 => reeseFilt.Q;
0.0 => reeseG.gain;
800.0 => float reeseFiltTarget;

// ============ PAD (3-voice chords) ============
TriOsc padOsc1 => LPF padFilt => Gain padG => master;
TriOsc padOsc2 => padFilt;
TriOsc padOsc3 => padFilt;
0.25 => padOsc1.gain; 0.25 => padOsc2.gain; 0.25 => padOsc3.gain;
1400.0 => padFilt.freq; 0.8 => padFilt.Q;
0.0 => padG.gain;
0.0 => float padAmpTarget;
0.0 => float padAmpCurrent;
-1 => int lastPadRoot;

// ============ LEAD (delayed sine, atmospheric) ============
SinOsc ldOsc => LPF ldFilt => Gain ldDry => master;
ldDry => DelayL ldDly => Gain ldWet => master;
0.5 => ldOsc.gain;
1800.0 => ldFilt.freq; 1.2 => ldFilt.Q;
0.0 => ldDry.gain;
0.35 => ldDly.gain;
0.38::second => ldDly.max;
(60.0 / BPM * 0.75)::second => ldDly.delay;  // dotted-eighth delay
0.0 => ldWet.gain;
0.0 => float ldAmpTarget;
0.0 => float ldAmpCurrent;
1800.0 => float ldFiltTarget;
-1 => int lastLdDeg;

// ============ STAB (chord hit) ============
SawOsc stab1 => LPF stabFilt => ADSR stabEnv => Gain stabG => master;
SawOsc stab2 => stabFilt;
SawOsc stab3 => stabFilt;
0.2 => stab1.gain; 0.2 => stab2.gain; 0.2 => stab3.gain;
2500.0 => stabFilt.freq; 2.0 => stabFilt.Q;
stabEnv.set(1::ms, 120::ms, 0.0, 60::ms);
0.0 => stabG.gain;

// ============ RISER ============
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

            if(energy >= 1) { 0.10 => snG.gain; 0.10 => subG.gain; 0.05 => ldDry.gain; 0.03 => ldWet.gain; }
            if(energy >= 2) { 0.06 => reeseG.gain; 0.05 => padG.gain; 0.06 => stabG.gain; }
            else { 0.0 => reeseG.gain; 0.0 => padAmpTarget; 0.0 => stabG.gain; }
        }
    }
}

// ============ MAIN SEQUENCER ============
while(true) {
    stepCount % 16 => int s;

    if(s == 0) {
        readState();
        barsSinceEvent + 1 => barsSinceEvent;

        if(transition > 0) {
            transitionBars - 1 => transitionBars;
            if(transitionBars <= 0) {
                if(transition == 2) { 3 => transition; 1 => transitionBars; }
                else { 0 => transition; 0.0 => riserG.gain; }
            }
        }

        if(barsSinceEvent > 6 && energy > 0 && transition == 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) { 0.0 => reeseG.gain; 0.0 => padAmpTarget; 0.0 => stabG.gain; }
            if(energy < 1) { 0.0 => snG.gain; 0.0 => subG.gain; 0.0 => ldAmpTarget; 0.0 => ldWet.gain; }
        }
        if(barsSinceEvent > 14) 0.0 => masterTarget;
    }

    transitionStep + 1 => transitionStep;
    0 => int kickMuted;
    0 => int hatFill;

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

    // ---- KICK ----
    if(!kickMuted && kPat[energy][s]) {
        0.0 => kickPh;
        0.8 => kickOsc.gain;
        kickClickEnv.keyOn();
    }

    // ---- SNARE ----
    if(snPat[energy][s]) snEnv.keyOn();

    // ---- HATS ----
    if(hatFill) { chEnv.keyOn(); }
    else { if(chPat[energy][s]) chEnv.keyOn(); }

    // ---- SUB BASS ----
    if(energy >= 1 && subPat[energy][s] >= 0) {
        Std.mtof(note(subPat[energy][s], 1)) => subOsc.freq;
        0.15 => subAmpTarget;
    }

    // ---- REESE ----
    if(energy >= 2 && s % 8 == 0) {
        Math.random2(0, 4) => int deg;
        Std.mtof(note(deg, 2)) => reese1.freq;
        reese1.freq() * 1.008 => reese2.freq;
        1200.0 + Math.random2f(0.0, 800.0) => reeseFiltTarget;
    }

    // ---- PAD CHORDS (change every 2 bars) ----
    if(energy >= 2 && s == 0 && stepCount % 32 == 0) {
        Math.random2(0, 4) => int root;
        if(root == lastPadRoot) (root + Math.random2(1, 3)) % 5 => root;
        root => lastPadRoot;
        Std.mtof(note(root, 3)) => padOsc1.freq;
        Std.mtof(note(root + 2, 3)) => padOsc2.freq;
        Std.mtof(note(root + 4, 3)) => padOsc3.freq;
        0.05 => padAmpTarget;
    }

    // ---- LEAD (melodic, with delay echo) ----
    if(energy >= 1 && Math.random2(0, 99) < 12 && ldAmpCurrent < 0.008) {
        [0, 2, 4, 7, 9] @=> int ldDegs[];
        ldDegs[Math.random2(0, 4)] => int deg;
        if(deg == lastLdDeg) ldDegs[(Math.random2(0, 4))] => deg;
        deg => lastLdDeg;
        4 + Math.random2(0, 1) => int ldOct;
        Std.mtof(note(deg, ldOct)) => ldOsc.freq;
        2000.0 + Math.random2f(0.0, 1500.0) => ldFiltTarget;
        0.05 => ldAmpTarget;
    }

    // ---- STAB (chord hits on offbeats) ----
    if(energy >= 2 && transition == 0) {
        if(s == 2 || s == 10 || (energy >= 3 && s == 6)) {
            if(lastPadRoot >= 0) {
                Std.mtof(note(lastPadRoot, 4)) => stab1.freq;
                Std.mtof(note(lastPadRoot + 2, 4)) => stab2.freq;
                Std.mtof(note(lastPadRoot + 4, 4)) => stab3.freq;
                stabEnv.keyOn();
            }
        }
    }

    // ---- SUBSTEP UPDATES ----
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        if(kickOsc.gain() > 0.005) {
            38.0 + 80.0 * Math.exp(-kickPh * 8.0) => kickOsc.freq;
            kickOsc.freq() * 4.0 => kickLPF.freq;
            kickOsc.gain() * 0.95 => kickOsc.gain;
            kickPh + 0.08 => kickPh;
        } else { 0.0 => kickOsc.gain; }

        if(impactG.gain() > 0.01) {
            impactG.gain() * 0.97 => impactG.gain;
            impactOsc.freq() * 0.998 => impactOsc.freq;
        } else { 0.0 => impactG.gain; 0.0 => impactOsc.gain; }

        riserBP.freq() + (riserFreqTarget - riserBP.freq()) * 0.05 => riserBP.freq;

        subAmpCurrent + (subAmpTarget - subAmpCurrent) * 0.05 => subAmpCurrent;
        subAmpCurrent => subG.gain;
        if(subAmpTarget > 0.01) subAmpTarget * 0.995 => subAmpTarget;

        reeseFilt.freq() + (reeseFiltTarget - reeseFilt.freq()) * 0.08 => reeseFilt.freq;
        if(reeseFiltTarget > 300.0) reeseFiltTarget * 0.996 => reeseFiltTarget;

        padAmpCurrent + (padAmpTarget - padAmpCurrent) * 0.008 => padAmpCurrent;
        padAmpCurrent => padG.gain;
        if(padAmpTarget > 0.005) padAmpTarget * 0.9985 => padAmpTarget;

        // Lead envelope + filter
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.04 => ldAmpCurrent;
        ldAmpCurrent => ldDry.gain;
        if(ldAmpTarget > 0.003) ldAmpTarget * 0.993 => ldAmpTarget;
        ldFilt.freq() + (ldFiltTarget - ldFilt.freq()) * 0.06 => ldFilt.freq;
        if(ldFiltTarget > 600.0) ldFiltTarget * 0.997 => ldFiltTarget;

        // Stab filter decay
        if(stabFilt.freq() > 800.0) stabFilt.freq() * 0.998 => stabFilt.freq;

        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain => master.gain;

        stepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
