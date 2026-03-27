// ambient.ck - Beatpilot Ambient Engine
// No drums. Slow evolving pads, drones, and shimmering textures.

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

Gain master => dac;
0.0 => master.gain;

[[0,2,4,7,9], [0,3,5,7,10], [0,2,4,5,7], [0,2,3,7,10]] @=> int scales[][];

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    if(degree < 0) return 0;
    return key + octave * 12 + scl[degree % scl.cap()] + (degree / scl.cap()) * 12;
}

// ============ DRONE (low pad, always present) ============
TriOsc drone1 => LPF droneFilt => Gain droneG => master;
TriOsc drone2 => droneFilt;
0.4 => drone1.gain; 0.4 => drone2.gain;
400.0 => droneFilt.freq; 1.0 => droneFilt.Q;
0.0 => droneG.gain;
0.0 => float droneAmpTarget;
0.0 => float droneAmpCurrent;

// ============ PAD (mid-range, slow chords) ============
SinOsc pad1 => LPF padFilt => Gain padG => master;
SinOsc pad2 => padFilt;
SinOsc pad3 => padFilt;
0.3 => pad1.gain; 0.3 => pad2.gain; 0.3 => pad3.gain;
2000.0 => padFilt.freq; 0.7 => padFilt.Q;
0.0 => padG.gain;
0.0 => float padAmpTarget;
0.0 => float padAmpCurrent;
-1 => int lastPadRoot;

// ============ SHIMMER (high sine, sparse) ============
SinOsc shimmer => Gain shimG => master;
0.0 => shimG.gain;
0.0 => float shimAmpTarget;
0.0 => float shimAmpCurrent;

// ============ SUB DRONE ============
SinOsc subDrone => LPF subFilt => Gain subG => master;
200.0 => subFilt.freq; 1.0 => subFilt.Q;
0.0 => subG.gain;
0.0 => float subAmpTarget;
0.0 => float subAmpCurrent;

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

            newEnergy => energy;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;
            1.0 => masterTarget;

            // Drone always on
            0.06 => droneAmpTarget;
            Std.mtof(note(0, 2)) => drone1.freq;
            drone1.freq() * 1.003 => drone2.freq;
            Std.mtof(note(0, 1)) => subDrone.freq;
            0.05 => subAmpTarget;

            if(energy >= 2) 0.04 => padAmpTarget;
        }
    }
}

// ============ MAIN LOOP ============
while(true) {
    stepCount % 16 => int s;

    if(s == 0) {
        readState();
        barsSinceEvent + 1 => barsSinceEvent;

        if(barsSinceEvent > 10 && energy > 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) 0.0 => padAmpTarget;
        }
        if(barsSinceEvent > 18) {
            0.0 => masterTarget;
            0.0 => droneAmpTarget;
            0.0 => subAmpTarget;
        }
    }

    // ---- PAD CHORD (change every 4 bars) ----
    if(energy >= 2 && s == 0 && stepCount % 64 == 0) {
        Math.random2(0, 4) => int root;
        if(root == lastPadRoot) (root + Math.random2(1, 3)) % 5 => root;
        root => lastPadRoot;
        Std.mtof(note(root, 3)) => pad1.freq;
        Std.mtof(note(root + 2, 3)) => pad2.freq;
        Std.mtof(note(root + 4, 4)) => pad3.freq;
        0.04 => padAmpTarget;
    }

    // ---- SHIMMER (rare, high notes) ----
    if(energy >= 1 && Math.random2(0, 99) < 3 && shimAmpCurrent < 0.005) {
        Math.random2(0, 4) => int deg;
        5 + Math.random2(0, 1) => int oct;
        Std.mtof(note(deg, oct)) => shimmer.freq;
        0.03 => shimAmpTarget;
    }

    // ---- SUBSTEP UPDATES ----
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        droneAmpCurrent + (droneAmpTarget - droneAmpCurrent) * 0.005 => droneAmpCurrent;
        droneAmpCurrent => droneG.gain;

        subAmpCurrent + (subAmpTarget - subAmpCurrent) * 0.005 => subAmpCurrent;
        subAmpCurrent => subG.gain;

        padAmpCurrent + (padAmpTarget - padAmpCurrent) * 0.008 => padAmpCurrent;
        padAmpCurrent => padG.gain;
        if(padAmpTarget > 0.003) padAmpTarget * 0.9998 => padAmpTarget;

        shimAmpCurrent + (shimAmpTarget - shimAmpCurrent) * 0.01 => shimAmpCurrent;
        shimAmpCurrent => shimG.gain;
        if(shimAmpTarget > 0.002) shimAmpTarget * 0.998 => shimAmpTarget;

        // Slow filter drift on drone
        400.0 + 300.0 * Math.sin(stepCount * 0.001) => droneFilt.freq;

        masterGain + (masterTarget - masterGain) * 0.008 => masterGain;
        masterGain => master.gain;

        stepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
