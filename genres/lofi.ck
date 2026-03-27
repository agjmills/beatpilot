// lofi.ck - Beatpilot Lo-fi / Chillhop Engine
// 85 BPM, mellow, jazzy, dusty

// ============ CLOCK ============
85.0 => float BPM;
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

Gain master => dac;
0.0 => master.gain;

// Jazzier scales: major 7, minor 7, dorian, lydian
[[0,2,4,7,11], [0,3,5,7,10], [0,2,3,5,9], [0,2,4,6,7]] @=> int scales[][];

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    if(degree < 0) return 0;
    return key + octave * 12 + scl[degree % scl.cap()] + (degree / scl.cap()) * 12;
}

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

// ============ HATS (soft, shuffled feel) ============
Noise chN => HPF chHP => ADSR chEnv => Gain chG => master;
7000.0 => chHP.freq;
chEnv.set(0.5::ms, 30::ms, 0.0, 10::ms);
0.03 => chG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0]] @=> int chPat[][];

// ============ BASS (warm, round) ============
SinOsc bassOsc => LPF bassFilt => Gain bassG => master;
0.6 => bassOsc.gain;
600.0 => bassFilt.freq; 1.5 => bassFilt.Q;
0.0 => bassG.gain;
0.0 => float bassAmpTarget;
0.0 => float bassAmpCurrent;

[[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1],
 [ 0,-1,-1,-1,-1,-1, 2,-1,-1,-1,-1,-1, 4,-1,-1,-1],
 [ 0,-1,-1, 4,-1,-1, 2,-1,-1,-1, 3,-1, 4,-1,-1,-1]] @=> int bPat[][];

// ============ KEYS (warm chords — the lo-fi heart) ============
TriOsc key1 => LPF keyFilt => Gain keyG => master;
TriOsc key2 => keyFilt;
TriOsc key3 => keyFilt;
0.3 => key1.gain; 0.3 => key2.gain; 0.3 => key3.gain;
1800.0 => keyFilt.freq; 1.0 => keyFilt.Q;
0.0 => keyG.gain;
0.0 => float keyAmpTarget;
0.0 => float keyAmpCurrent;
-1 => int lastChordRoot;

// ============ VINYL CRACKLE ============
Noise vinyl => HPF vinylHP => LPF vinylLP => Gain vinylG => master;
4000.0 => vinylHP.freq;
8000.0 => vinylLP.freq;
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

            newEnergy => energy;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;
            1.0 => masterTarget;

            if(energy >= 1) { 0.06 => snG.gain; 0.10 => bassG.gain; 0.012 => vinylG.gain; }
            if(energy >= 2) { 0.06 => keyG.gain; }
            else { 0.0 => keyAmpTarget; }
        }
    }
}

// ============ MAIN SEQUENCER ============
while(true) {
    stepCount % 16 => int s;

    if(s == 0) {
        readState();
        barsSinceEvent + 1 => barsSinceEvent;

        if(barsSinceEvent > 8 && energy > 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) 0.0 => keyAmpTarget;
            if(energy < 1) { 0.0 => snG.gain; 0.0 => bassG.gain; 0.0 => vinylG.gain; }
        }
        if(barsSinceEvent > 14) 0.0 => masterTarget;
    }

    // ---- KICK (soft thump) ----
    if(kPat[energy][s]) {
        0.0 => kickPh;
        0.6 => kickOsc.gain;
    }

    // ---- SNARE ----
    if(snPat[energy][s]) snEnv.keyOn();

    // ---- HATS ----
    if(chPat[energy][s]) chEnv.keyOn();

    // ---- BASS ----
    if(energy >= 1 && bPat[energy][s] >= 0) {
        Std.mtof(note(bPat[energy][s], 2)) => bassOsc.freq;
        0.10 => bassAmpTarget;
    }

    // ---- KEYS (chord changes every 2 bars, probabilistic) ----
    if(energy >= 2 && s == 0 && stepCount % 32 == 0) {
        Math.random2(0, 4) => int root;
        if(root == lastChordRoot) (root + Math.random2(1, 3)) % 5 => root;
        root => lastChordRoot;
        Std.mtof(note(root, 3)) => key1.freq;
        Std.mtof(note(root + 2, 3)) => key2.freq;
        Std.mtof(note(root + 4, 3)) => key3.freq;
        0.06 => keyAmpTarget;
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

        // Bass amp
        bassAmpCurrent + (bassAmpTarget - bassAmpCurrent) * 0.04 => bassAmpCurrent;
        bassAmpCurrent => bassG.gain;
        if(bassAmpTarget > 0.01) bassAmpTarget * 0.997 => bassAmpTarget;

        // Keys amp (slow swell and fade)
        keyAmpCurrent + (keyAmpTarget - keyAmpCurrent) * 0.01 => keyAmpCurrent;
        keyAmpCurrent => keyG.gain;
        if(keyAmpTarget > 0.005) keyAmpTarget * 0.9985 => keyAmpTarget;

        masterGain + (masterTarget - masterGain) * 0.015 => masterGain;
        masterGain => master.gain;

        stepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
