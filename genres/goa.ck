// engine.ck - Beatpilot Goa Trance Engine
// Driving 4/4 kick, rolling acid bass, eastern modes (phrygian/hijaz/harmonic minor),
// psychedelic FM lead drenched in delay, off-beat open hats — classic goa.
// Reads state from /tmp/beatpilot-state.

// ============ SAMPLE DETECTION ============
me.dir() + "/../samples/goa/" => string smpDir;
0 => int useSamples;

// ============ CLOCK ============
145.0 => float BPM;
(60.0 / BPM / 4.0)::second => dur stepDur;
4 => int SUBSTEPS;
0.5 => float swingAmt; // goa is straight — driving, no shuffle

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
0 => int variant;
0 => int drumFill;

// ============ FX STATE ============
0 => int fxType;
0 => int fxBar;
0 => int fxLen;

// ============ INTRO STATE ============
0 => int introActive;
0 => int introBar;
0 => int introLen;

// ============ PHRASE / SONG STRUCTURE ============
// Goa progressions stay in dark/eastern territory — minor i, II (phrygian), v, iv
[[0, 1, 0, 4], [0, 4, 1, 0], [0, 3, 4, 1], [0, 1, 3, 0]] @=> int progs[][];
0 => int progIdx;
0 => int chordIdx;
0 => int chordRoot;
0 => int phraseBar;
0 => int phraseRepeat;
int chordSub[4];

64 => int PHRASE_LEN;
int motif[64];
int bassLine[64];
0 => int motifGenerated;
0 => int phraseStep;

int arrangement[16];

fun void generateMotif() {
    seed => int s;
    for(0 => int i; i < PHRASE_LEN; i++) -1 => motif[i];

    // Goa cell: tight intervals, often climbing — eastern feel
    int cellDeg[3];
    int cellPos[3];
    0 => cellDeg[0];
    [1, 2, 1, -1, 2, 3] @=> int leaps[];
    leaps[s % leaps.cap()] => int leap1;
    leap1 => cellDeg[1];
    [1, 2, -1, 1, 0] @=> int resolves[];
    cellDeg[1] + resolves[(s / 2) % resolves.cap()] => cellDeg[2];

    // Goa rhythm: tight, driving — every other 16th
    [[0, 2, 4], [0, 2, 6], [2, 4, 6], [0, 4, 6], [0, 2, 8]] @=> int cellRhythms[][];
    cellRhythms[(s / 3) % cellRhythms.cap()] @=> int cR[];
    cR[0] => cellPos[0]; cR[1] => cellPos[1]; cR[2] => cellPos[2];

    s % 3 => int varType;

    // Bar 1: cell
    for(0 => int i; i < 3; i++) cellDeg[i] => motif[cellPos[i]];

    // Bar 2: cell varied
    if(varType == 0) {
        for(0 => int i; i < 3; i++) cellDeg[i] + 2 => motif[16 + cellPos[i]];
    } else if(varType == 1) {
        cellDeg[2] => motif[16 + cellPos[0]];
        cellDeg[1] => motif[16 + cellPos[1]];
        cellDeg[0] => motif[16 + cellPos[2]]; // retrograde
    } else {
        for(0 => int i; i < 3; i++) cellDeg[i] - 1 => motif[16 + cellPos[i]];
    }

    // Bar 3: ascending climax — classic goa "up the scale" peak
    for(0 => int i; i < 3; i++) cellDeg[i] + 4 => motif[32 + cellPos[i]];
    cellDeg[1] + 4 => motif[32 + 8];
    cellDeg[2] + 4 => motif[32 + 10];
    cellDeg[0] + 5 => motif[32 + 12];
    cellDeg[1] + 5 => motif[32 + 14];

    // Bar 4: descend back to root
    cellDeg[2] => motif[48];
    cellDeg[1] => motif[52];
    cellDeg[0] => motif[56];
    0 => motif[60];

    // --- ROLLING ACID BASS LINE ---
    // Goa bass = constant 16ths, nearly every step. The squelch IS the genre.
    for(0 => int i; i < PHRASE_LEN; i++) -1 => bassLine[i];

    // Every step gets a note in goa — rolling river of bass
    // Most are root, with cell intervals as decoration
    for(0 => int i; i < 64; i++) {
        if(i % 4 == 0) 0 => bassLine[i];           // downbeat: root
        else if(i % 8 == 6) cellDeg[1] => bassLine[i]; // syncopated cell tone
        else if(i % 4 == 2) 0 => bassLine[i];       // off: root
        else if((s + i) % 3 == 0) -1 => bassLine[i]; // occasional rest
        else 0 => bassLine[i];                      // most: root
    }

    // Bar 3: bass climbs with the lead — peak energy
    cellDeg[1] => bassLine[34];
    cellDeg[2] => bassLine[38];
    2 => bassLine[42];
    3 => bassLine[46];

    // --- ARRANGEMENT ---
    s % 3 => int arrType;
    if(arrType == 0) {
        // Build from bass, layer pad, drop lead, breakdown briefly, slam back
        [1,1,1,1, 2,2,3,3, 3,3,3,3, 1,1,3,3] @=> int arrA[];
        for(0 => int i; i < 16; i++) arrA[i] => arrangement[i];
    } else if(arrType == 1) {
        // Long peak — lead carries most of the phrase
        [2,2,3,3, 3,3,3,3, 3,3,3,3, 2,2,1,1] @=> int arrB[];
        for(0 => int i; i < 16; i++) arrB[i] => arrangement[i];
    } else {
        // Pulse: lead drops in and out for tension
        [2,2,2,2, 3,3,3,3, 2,2,2,2, 3,3,3,3] @=> int arrC[];
        for(0 => int i; i < 16; i++) arrC[i] => arrangement[i];
    }

    0 => phraseStep;
    1 => motifGenerated;
}

// ============ TRANSITION STATE ============
0 => int transition;
0 => int transitionBars;
0 => int transitionStep;

// ============ VOICE TRIGGER STATE ============
0 => int voiceCooldown;  // bars to wait before next voice trigger
0 => int voiceLastIdx;   // last sample index used (avoid repeats)

// ============ MASTER BUS ============
Gain masterOut => HPF fxHPF => dac;
20.0 => fxHPF.freq; 0.8 => fxHPF.Q;
Gain master => masterOut;
0.0 => master.gain;

// ============ SAMPLE BUFFERS ============
SndBuf smpKick => Gain smpKickG => master;
SndBuf smpHat => Gain smpHatG => master;
SndBuf smpHatOpen => Gain smpHatOpenG => master;
SndBuf smpClap => Gain smpClapG => master;
0.0 => smpKickG.gain; 0.0 => smpHatG.gain;
0.0 => smpHatOpenG.gain; 0.0 => smpClapG.gain;

FileIO smpTest;
if(smpTest.open(smpDir + "kick.wav", FileIO.READ)) {
    smpTest.close();
    smpKick.read(smpDir + "kick.wav");
    smpHat.read(smpDir + "hat_closed.wav");
    smpHatOpen.read(smpDir + "hat_open.wav");
    smpClap.read(smpDir + "clap.wav");
    smpKick.samples() => smpKick.pos;
    smpHat.samples() => smpHat.pos;
    smpHatOpen.samples() => smpHatOpen.pos;
    smpClap.samples() => smpClap.pos;
    1 => useSamples;
    <<< "Beatpilot [goa]: samples loaded" >>>;
} else {
    <<< "Beatpilot [goa]: no samples found, using synthesis" >>>;
}

// ============ VOICE SAMPLES (the goa staple) ============
// Up to 8 voice clips loaded from samples/goa/voice/voice_*.wav
// Played sparingly — at phrase boundaries, breakdowns, new phases.
// Routes through the lead delay for that classic goa cinematic-with-echo feel.
SndBuf voice1 => Gain voiceG => master;
SndBuf voice2 => voiceG;
SndBuf voice3 => voiceG;
SndBuf voice4 => voiceG;
SndBuf voice5 => voiceG;
SndBuf voice6 => voiceG;
SndBuf voice7 => voiceG;
SndBuf voice8 => voiceG;
0.7 => voiceG.gain;
SndBuf @ voices[8];
voice1 @=> voices[0]; voice2 @=> voices[1]; voice3 @=> voices[2]; voice4 @=> voices[3];
voice5 @=> voices[4]; voice6 @=> voices[5]; voice7 @=> voices[6]; voice8 @=> voices[7];
0 => int voiceCount;
me.dir() + "/../samples/goa/voice/" => string voiceDir;
for(0 => int vi; vi < 8; vi++) {
    voiceDir + "voice_" + (vi + 1) + ".wav" => string vpath;
    FileIO vTest;
    if(vTest.open(vpath, FileIO.READ)) {
        vTest.close();
        voices[vi].read(vpath);
        voices[vi].samples() => voices[vi].pos; // start silent
        vi + 1 => voiceCount;
    }
}
if(voiceCount > 0) <<< "Beatpilot [goa]: ", voiceCount, " voice samples loaded" >>>;

// ============ SCALES (eastern/exotic 5-note pools) ============
// 0: phrygian pentatonic (root, b2, b3, 5, b7) — dark eastern
// 1: hijaz pentatonic (root, b2, M3, 5, b6) — exotic, augmented 2nd
// 2: harmonic minor pentatonic (root, b3, 5, b6, M7) — cinematic
// 3: phrygian dominant pentatonic (root, b2, M3, 5, b7) — flamenco/goa staple
[[0,1,3,7,10], [0,1,4,7,8], [0,3,7,8,11], [0,1,4,7,10]] @=> int scales[][];

fun int note(int degree, int octave) {
    scales[scaleType] @=> int scl[];
    if(degree < 0) return 0;
    return key + octave * 12 + scl[degree % scl.cap()] + (degree / scl.cap()) * 12;
}

// ============ KICK (deep, punchy 4/4) ============
SinOsc kickOsc => LPF kickLPF => Gain kickG => master;
0.0 => kickOsc.gain;
300.0 => kickLPF.freq;
0.4 => kickG.gain;
0.0 => float kickPh;
Noise kickClick => BPF kickClickBP => ADSR kickClickEnv => kickG;
3500.0 => kickClickBP.freq; 1.5 => kickClickBP.Q;
kickClickEnv.set(0.2::ms, 8::ms, 0.0, 3::ms);
0.3 => kickClick.gain;

// Goa: pure 4-on-floor at all energies above 0
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],
 [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0]] @=> int kPat[][];

[1.0, 0.3, 0.6, 0.3, 0.95, 0.3, 0.6, 0.4, 0.95, 0.3, 0.6, 0.3, 0.9, 0.35, 0.6, 0.5] @=> float hatVel[];
[1.0, 0.0, 0.0, 0.0, 0.95, 0.0, 0.0, 0.0, 0.95, 0.0, 0.0, 0.0, 0.9, 0.0, 0.0, 0.0] @=> float kickVel[];

// ============ CLOSED HAT ============
Noise chN => HPF chHP => ADSR chEnv => Gain chG => master;
9000.0 => chHP.freq;
chEnv.set(0.3::ms, 18::ms, 0.0, 5::ms);
0.06 => chG.gain;

// Closed hats fill in 16ths at higher energy
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0],
 [0,1,1,0,0,1,1,0,0,1,1,0,0,1,1,0],
 [1,1,1,0,1,1,1,0,1,1,1,0,1,1,1,0]] @=> int chPat[][];

// ============ OPEN HAT (classic trance off-beats) ============
Noise ohN => BPF ohBP => ADSR ohEnv => Gain ohG => master;
9500.0 => ohBP.freq; 1.8 => ohBP.Q;
ohEnv.set(1::ms, 180::ms, 0.04, 120::ms);
0.06 => ohG.gain;

// Open hat on every off-beat (steps 4, 12) at energy 2+ — the trance pulse
[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0]] @=> int ohPat[][];

// ============ ACID BASS (the goa squelch) ============
// Saw + sub-sine through resonant LPF with per-note envelope
SawOsc bassOsc1 => LPF bassF => Gain bassG => master;
SawOsc bassOsc2 => bassF;  // detuned partner
SinOsc bassSub => Gain bassSubG => master;  // sub layer
0.5 => bassOsc1.gain; 0.4 => bassOsc2.gain;
0.0 => bassSub.gain; 0.5 => bassSubG.gain;
600.0 => bassF.freq; 6.0 => bassF.Q;  // high resonance = squelch
0.18 => bassG.gain;
1500.0 => float bassFiltTarget;
0.0 => float bassEnv;        // per-note amplitude env
0.0 => float bassFiltEnv;    // per-note filter env
0.0 => float bassDriftPhase;

// ============ LEAD (psychedelic FM) ============
// FM synth: carrier + modulator with high mod depth = trance lead
SinOsc ldMod => SinOsc ldOsc => LPF ldF => Gain ldDry => master;
SinOsc ldOsc2 => ldF;  // detuned partner for width
3 => ldOsc.sync;   // FM mode
0.0 => ldOsc.gain; 0.0 => ldOsc2.gain;
3000.0 => ldF.freq; 1.2 => ldF.Q;
0.0 => ldDry.gain;
3000.0 => float ldFiltTarget;
0.0 => float ldAmpTarget;
0.0 => float ldAmpCurrent;
0.0 => float ldModDepthTarget;
0.0 => float ldModDepth;

// Goa lead delay: 3/16 (dotted-eighth) for that classic psy-echo
ldDry => Delay ldDly1 => Gain ldDlyFb => LPF ldDlyF => master;
ldDlyFb => ldDly1;
(stepDur * 3) => ldDly1.max => ldDly1.delay;
0.55 => ldDlyFb.gain;   // longer feedback tail than techno
0.10 => ldDly1.gain;    // wetter — delay is part of the sound
2200.0 => ldDlyF.freq;

// Second delay: quarter-note for ping-pong feel
ldDry => Delay ldDly2 => Gain ldDlyFb2 => LPF ldDlyF2 => master;
ldDlyFb2 => ldDly2;
(stepDur * 4) => ldDly2.max => ldDly2.delay;
0.40 => ldDlyFb2.gain;
0.05 => ldDly2.gain;
1800.0 => ldDlyF2.freq;

// Route voice into the delay lines for echo trails
voiceG => ldDly1;
voiceG => ldDly2;

// ============ PAD (atmospheric, slow) ============
TriOsc padOsc1 => LPF padF => Gain padG => master;
SinOsc padOsc2 => padF;
TriOsc padOsc3 => padF;
0.22 => padOsc1.gain; 0.28 => padOsc2.gain; 0.18 => padOsc3.gain;
500.0 => padF.freq; 1.6 => padF.Q;
0.0 => padG.gain;
0.0 => float padGainTarget;
500.0 => float padFiltTarget;
0.0 => float padLfoPhase;

// ============ CLAP (on 2 and 4) ============
Noise clpN => BPF clpBP => ADSR clpEnv => Gain clpG => master;
1300.0 => clpBP.freq; 2.2 => clpBP.Q;
clpEnv.set(0.5::ms, 70::ms, 0.0, 25::ms);
0.0 => clpG.gain;

[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],
 [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0]] @=> int clpPat[][];

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
            seed % progs.cap() => progIdx;
            0 => phraseBar;
            0 => chordIdx;
            0 => phraseRepeat;
            for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
            progs[progIdx][0] => chordRoot;
            generateMotif();

            if(transition == 0 && energy >= 1) {
                if(newEnergy >= 3 && energy < 3) {
                    2 => transition;
                    3 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy >= 2 && newEnergy > energy) {
                    2 => transition;
                    2 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy == 0) {
                    4 => transition;
                    2 => transitionBars;
                    0 => transitionStep;
                } else if(newEnergy < energy && energy >= 2) {
                    4 => transition;
                    1 => transitionBars;
                    0 => transitionStep;
                }
            }

            newEnergy => energy;
            if(energy > 3) 3 => energy;
            if(energy < 0) 0 => energy;
            0 => barsSinceEvent;

            // Goa intro: HPF starts very high, big sweep down
            if(masterTarget < 0.01 && newEnergy >= 2) {
                if((seed + newSeed) % 2 == 0) {
                    1 => introActive;
                    0 => introBar;
                    if((seed * 3 + newSeed) % 2 == 0) 4 => introLen;
                    else 8 => introLen;  // goa intros are long
                    3500.0 => fxHPF.freq;
                }
            }

            1.0 => masterTarget;

            if(energy >= 2) {
                0.10 => ldDry.gain;
                0.10 => clpG.gain;
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

    if(s == 0) {
        readState();
        FileIO vf;
        if(vf.open("/tmp/beatpilot-volume", FileIO.READ)) {
            Std.atoi(vf.readLine()) => int vol;
            vf.close();
            if(vol >= 0 && vol <= 100) vol / 100.0 => volume;
        }
        barsSinceEvent + 1 => barsSinceEvent;

        if(transition > 0) {
            transitionBars - 1 => transitionBars;
            if(transitionBars <= 0) {
                if(transition == 2) {
                    3 => transition;
                    1 => transitionBars;
                } else {
                    0 => transition;
                    0 => riserG.gain;
                }
            }
        }

        phraseBar + 1 => phraseBar;
        if(phraseBar >= 16) {
            0 => phraseBar;
            phraseRepeat + 1 => phraseRepeat;
            for(0 => int ci; ci < 4; ci++) -1 => chordSub[ci];
            // Goa chord sub: shift up 1 degree (semitone in phrygian = chromatic tension)
            if(phraseRepeat % 3 == 2 && energy >= 2) {
                (seed * 13 + phraseRepeat) % 4 => int subIdx;
                (progs[progIdx][subIdx] + 1) % 5 => chordSub[subIdx];
            }
            // NEW PHASE: every 4 phrase repeats, shift to a new section
            if(phraseRepeat % 4 == 0 && phraseRepeat > 0 && energy >= 1 && transition == 0) {
                (seed + phraseRepeat * 7 + 31) % 256 => seed;
                seed % progs.cap() => progIdx;
                seed % scales.cap() => scaleType;
                progs[progIdx][0] => chordRoot;
                generateMotif();
                4 => transition;
                2 => transitionBars;
                0 => transitionStep;
                <<< "Beatpilot [goa]: new phase" >>>;
                // Voice trigger on new phase — guaranteed cinematic moment
                if(voiceCount > 0 && voiceCooldown == 0) {
                    (seed + phraseRepeat) % voiceCount => int vIdx;
                    if(vIdx == voiceLastIdx && voiceCount > 1) (vIdx + 1) % voiceCount => vIdx;
                    vIdx => voiceLastIdx;
                    0 => voices[vIdx].pos;
                    8 => voiceCooldown;
                }
            }
        }
        phraseBar / 4 => chordIdx;
        if(chordIdx >= progs[progIdx].cap()) 0 => chordIdx;
        progs[progIdx][chordIdx] => chordRoot;
        if(chordSub[chordIdx] >= 0) chordSub[chordIdx] => chordRoot;

        if(barsSinceEvent > 6 && energy > 0 && transition == 0) {
            energy - 1 => energy;
            0 => barsSinceEvent;
            if(energy < 2) {
                0.0 => ldAmpTarget;
                0.0 => clpG.gain;
            }
        }

        if(barsSinceEvent > 10 && energy == 0 && transition == 0) {
            0.0 => masterTarget;
        }

        0 => drumFill;
        if(energy >= 1 && motifGenerated) {
            if(phraseBar == 15) 2 => drumFill;
            else if(phraseBar % 4 == 3) 1 => drumFill;
        }

        // Voice cooldown decay
        if(voiceCooldown > 0) voiceCooldown - 1 => voiceCooldown;

        // Voice trigger: every 4 bars (bars 4, 8, 12 of each phrase) at ~50% chance
        // when energy >= 2. Cooldown prevents stacking.
        if(voiceCount > 0 && voiceCooldown == 0 && energy >= 2 && transition == 0) {
            if(phraseBar == 4 || phraseBar == 8 || phraseBar == 12) {
                (seed * 11 + phraseBar * 3 + stepCount / 16) % 5 => int vRoll;
                if(vRoll < 3) {
                    (seed * 7 + phraseBar + stepCount / 256) % voiceCount => int vIdx;
                    if(vIdx == voiceLastIdx && voiceCount > 1) (vIdx + 1) % voiceCount => vIdx;
                    vIdx => voiceLastIdx;
                    0 => voices[vIdx].pos;
                    8 => voiceCooldown;
                    <<< "Beatpilot [goa]: voice ", vIdx + 1 >>>;
                }
            }
        }

        // INTRO: long sweeping filter open
        if(introActive) {
            introBar + 1 => introBar;
            if(introBar > introLen) {
                0 => introActive;
                20.0 => fxHPF.freq;
                0.55 => ldDlyFb.gain;
                0.10 => ldDly1.gain;
            } else {
                introBar $ float / introLen $ float => float p;
                3500.0 * (1.0 - p) * (1.0 - p) + 20.0 => fxHPF.freq;
                0.70 => ldDlyFb.gain;
                0.14 => ldDly1.gain;
            }
        }

        // FX moments
        if(fxType == 0 && energy >= 2 && motifGenerated && phraseBar == 12 && transition == 0 && !introActive) {
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
                    20.0 + p * p * 2500.0 => fxHPF.freq;
                } else if(fxType == 2) {
                    1.6 + p * 7.0 => padF.Q;
                    padFiltTarget + p * 1000.0 => padF.freq;
                } else if(fxType == 3) {
                    0.55 + p * 0.35 => ldDlyFb.gain;
                    0.10 + p * 0.06 => ldDly1.gain;
                }
            }
        }
        if(fxType == 0 && !introActive) {
            if(padF.Q() > 1.7) padF.Q() * 0.92 + 1.6 * 0.08 => padF.Q;
            if(ldDlyFb.gain() > 0.56) ldDlyFb.gain() * 0.95 + 0.55 * 0.05 => ldDlyFb.gain;
            if(ldDly1.gain() > 0.105) ldDly1.gain() * 0.93 + 0.10 * 0.07 => ldDly1.gain;
        }
    }

    transitionStep + 1 => transitionStep;

    0 => int kickMuted;
    0 => int hatFill;

    if(transition == 2) {
        1 => kickMuted;
        0.07 + transitionStep * 0.0005 => float rGain;
        if(rGain > 0.13) 0.13 => rGain;
        rGain => riserG.gain;
        500.0 + transitionStep * 90.0 => riserFreqTarget;
        if(riserFreqTarget > 14000.0) 14000.0 => riserFreqTarget;
        if(transitionBars <= 1 && s >= 8) 1 => hatFill;
    } else if(transition == 3) {
        0 => transition;
        0 => riserG.gain;
        0.5 => impactG.gain;
        45.0 => impactOsc.freq;
        0.9 => impactOsc.gain;
        if(s == 0) {
            0.0 => kickPh;
            1.0 => kickOsc.gain;
            kickClickEnv.keyOn();
        }
    } else if(transition == 4) {
        1 => kickMuted;
        300.0 => bassFiltTarget;
        500.0 => ldFiltTarget;
        0.0 => ldAmpTarget;
    }

    // ---- KICK ----
    if(!kickMuted && kPat[energy][s]) {
        0.0 => kickPh;
        ((seed * 17 + stepCount) % 100 - 50) / 1000.0 => float velDrift;
        0.5 + 0.5 * (kickVel[s] + velDrift) => float kVel;
        if(useSamples) {
            0 => smpKick.pos;
            kVel * 0.12 => smpKickG.gain;
        }
        kVel * 0.85 => kickOsc.gain;
        kVel * 0.3 => kickClick.gain;
        if(useSamples) { kickOsc.gain() * 0.3 => kickOsc.gain; kickClick.gain() * 0.3 => kickClick.gain; }
        kickClickEnv.keyOn();
    }

    // ---- HATS ----
    if(hatFill) {
        (s $ float) / 16.0 => float fillVel;
        if(useSamples) { 0 => smpHat.pos; 0.08 + 0.10 * fillVel => smpHatG.gain; }
        0.03 + 0.07 * fillVel => chG.gain;
        if(useSamples) chG.gain() * 0.3 => chG.gain;
        chEnv.keyOn();
        if(s % 2 == 0) {
            if(useSamples) { 0 => smpHatOpen.pos; 0.08 => smpHatOpenG.gain; }
            ohEnv.keyOn();
        }
    } else {
        if(chPat[energy][s]) {
            if(useSamples) { 0 => smpHat.pos; 0.07 + 0.09 * hatVel[s] => smpHatG.gain; }
            0.025 + 0.05 * hatVel[s] => chG.gain;
            if(useSamples) chG.gain() * 0.3 => chG.gain;
            chEnv.keyOn();
        }
        if(ohPat[energy][s]) {
            if(useSamples) { 0 => smpHatOpen.pos; 0.08 + 0.09 * hatVel[s] => smpHatOpenG.gain; }
            0.04 + 0.05 * hatVel[s] => ohG.gain;
            if(useSamples) ohG.gain() * 0.3 => ohG.gain;
            ohEnv.keyOn();
        }
    }

    // ---- CLAP ----
    if(clpPat[energy][s]) {
        if(useSamples) { 0 => smpClap.pos; 0.18 => smpClapG.gain; }
        clpEnv.keyOn();
    }

    // ---- DRUM MICRO-VARIATION ----
    if(energy >= 2) {
        (seed + phraseBar * 7) % 8 => int drumVar;
        if(drumVar < 3 && s == 11 && !chPat[energy][s]) {
            0.025 => chG.gain;
            chEnv.keyOn();
        }
        if(drumVar >= 6 && s == 5 && !ohPat[energy][s]) {
            0.02 => ohG.gain;
            ohEnv.keyOn();
        }
    }

    // ---- DRUM FILL ----
    if(drumFill > 0 && energy >= 1) {
        if(drumFill == 2) {
            if(s >= 2 && !chPat[energy][s]) {
                0.03 + (s $ float) / 16.0 * 0.06 => chG.gain;
                chEnv.keyOn();
            }
            if(s >= 8 && s % 2 == 0) {
                0.04 + (s $ float) / 16.0 * 0.05 => clpG.gain;
                clpEnv.keyOn();
            }
            if(s >= 12) {
                0.04 + (s - 12) / 4.0 * 0.05 => ohG.gain;
                ohEnv.keyOn();
            }
        } else {
            if(s >= 12 && !chPat[energy][s]) {
                0.04 + (s - 12) / 4.0 * 0.05 => chG.gain;
                chEnv.keyOn();
            }
        }
    }

    // ---- ARRANGEMENT ----
    0 => int arrLevel;
    if(motifGenerated) arrangement[phraseBar] => arrLevel;
    if(energy < 2) { if(arrLevel > 1) 1 => arrLevel; }

    // ---- ACID BASS (rolling 16ths with per-note envelope = squelch) ----
    if(transition != 4 && energy >= 1 && arrLevel >= 1 && motifGenerated) {
        bassLine[phraseStep % PHRASE_LEN] => int bDeg;
        if(bDeg >= 0) {
            (bDeg + chordRoot) % 5 => bDeg;
            if(bDeg < 0) bDeg + 5 => bDeg;
            // Goa bass octave: 2 normally, 3 on accents
            2 => int bassOct;
            if(phraseStep % 8 == 6) 3 => bassOct;
            note(bDeg, bassOct) => int bassMidi;
            Std.mtof(bassMidi) => float bf;
            bf => bassOsc1.freq;
            bf * 1.003 => bassOsc2.freq;  // detune for thickness
            Std.mtof(bassMidi - 12) => bassSub.freq;
            // Trigger envelope: amplitude pluck + filter sweep
            1.0 => bassEnv;
            // Filter env target: opens up on accents, climbs in bar 3
            if(phraseStep >= 32 && phraseStep < 48) {
                2500.0 + Math.random2f(0.0, 1500.0) => bassFiltEnv;
            } else if(phraseStep % 4 == 0) {
                1800.0 => bassFiltEnv;
            } else {
                900.0 + Math.random2f(0.0, 600.0) => bassFiltEnv;
            }
        }
    }

    // ---- PAD ----
    if(transition != 4 && s == 0 && arrLevel >= 2) {
        chordRoot => int pRoot;
        chordRoot + 2 => int pDeg2;
        chordRoot + 4 => int pDeg3;
        Std.mtof(note(pRoot, 4)) => padOsc1.freq;
        Std.mtof(note(pDeg2, 4)) => padOsc2.freq;
        Std.mtof(note(pDeg3, 4)) => padOsc3.freq;
        padOsc1.freq() * 0.998 => padOsc1.freq;
        padOsc3.freq() * 1.002 => padOsc3.freq;
        phraseBar % 4 => int barInChord;
        if(barInChord < 2) 0.04 => padGainTarget;
        else if(barInChord == 2) 0.08 => padGainTarget;
        else 0.03 => padGainTarget;
        if(energy >= 3) padGainTarget * 1.3 => padGainTarget;
        500.0 + barInChord * 200.0 => padFiltTarget;
    } else if(arrLevel < 2) {
        0.0 => padGainTarget;
    }

    // ---- LEAD (psychedelic FM) ----
    if(transition != 4 && motifGenerated && arrLevel >= 3) {
        motif[phraseStep % PHRASE_LEN] => int deg;
        phraseBar / 4 => int motifRep;
        if(motifRep == 1 && (seed + phraseStep) % 5 == 0) -1 => deg;
        if(motifRep == 3 && deg >= 0 && phraseStep % 8 == 6) deg + 1 => deg;
        if(deg >= 0) {
            (deg + chordRoot) % 5 => deg;
            if(deg < 0) deg + 5 => deg;
            5 => int ldOct;
            if(motifRep == 2 && phraseStep >= 32) 6 => ldOct;
            note(deg, ldOct) => int ldMidi;
            Std.mtof(ldMidi) => float lf;
            lf => ldOsc.freq;
            lf * 1.005 => ldOsc2.freq;  // detune partner
            // FM mod ratio: 3:2 (bell-like) or 2:1 (warm) — varies per rep for color
            if(motifRep == 0) lf * 2.0 => ldMod.freq;
            else if(motifRep == 1) lf * 3.0 => ldMod.freq;
            else if(motifRep == 2) lf * 1.5 => ldMod.freq;
            else lf * 4.0 => ldMod.freq;
            // Mod depth: high = psychedelic edge
            150.0 + Math.random2f(0.0, 80.0) => ldModDepthTarget;
            phraseStep % 16 => int localStep;
            0.05 => float ldVel;
            if(localStep % 4 == 0) 0.10 => ldVel;
            else if(localStep % 2 == 0) 0.07 => ldVel;
            if(phraseStep >= 32 && phraseStep < 48) ldVel * 1.3 => ldVel;
            if(phraseStep >= 48) ldVel * 0.7 => ldVel;
            // Lead filter: opens on the climb in bar 3
            if(phraseStep >= 32 && phraseStep < 48) {
                3500.0 + Math.random2f(0.0, 1500.0) => ldFiltTarget;
            } else {
                1500.0 + Math.random2f(0.0, 800.0) => ldFiltTarget;
            }
            ldVel => ldAmpTarget;
        }
    } else if(arrLevel < 3) {
        0.0 => ldAmpTarget;
    }

    // Advance phrase step
    if(motifGenerated) {
        phraseStep + 1 => phraseStep;
        if(phraseStep >= PHRASE_LEN) 0 => phraseStep;
    }

    // ---- SUBSTEP ENVELOPE UPDATES ----
    stepDur => dur thisStepDur;
    if(s % 2 == 0) {
        stepDur * 2.0 * swingAmt => thisStepDur;
    } else {
        stepDur * 2.0 * (1.0 - swingAmt) => thisStepDur;
    }
    for(0 => int sub; sub < SUBSTEPS; sub++) {
        // Kick pitch envelope
        if(kickOsc.gain() > 0.005) {
            40.0 + 90.0 * Math.exp(-kickPh * 8.0) => kickOsc.freq;
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

        // Riser
        riserBP.freq() + (riserFreqTarget - riserBP.freq()) * 0.05 => riserBP.freq;

        // ACID BASS envelope decay (the squelch)
        // Amp: pluck and decay
        bassEnv * 0.92 => bassEnv;
        bassEnv * 0.18 => bassG.gain;
        bassEnv * 0.10 => bassSub.gain;
        // Filter: pluck and decay toward a low resting value
        bassFiltEnv * 0.93 + 600.0 * 0.07 => bassFiltEnv;
        bassF.freq() + (bassFiltEnv - bassF.freq()) * 0.20 => bassF.freq;
        // Slow pitch drift on the second osc — adds organic life
        bassDriftPhase + 0.0001 => bassDriftPhase;
        bassOsc1.freq() * (1.003 + Math.sin(bassDriftPhase) * 0.001) => bassOsc2.freq;

        // Lead filter
        ldF.freq() + (ldFiltTarget - ldF.freq()) * 0.04 => ldF.freq;
        if(ldFiltTarget > 1500.0) ldFiltTarget * 0.999 => ldFiltTarget;

        // Lead amplitude env
        ldAmpCurrent + (ldAmpTarget - ldAmpCurrent) * 0.05 => ldAmpCurrent;
        ldAmpCurrent => ldDry.gain;
        if(ldAmpTarget > 0.01) ldAmpTarget * 0.985 => ldAmpTarget;

        // FM mod depth smooth + apply
        ldModDepth + (ldModDepthTarget - ldModDepth) * 0.05 => ldModDepth;
        ldModDepth => ldMod.gain;
        if(ldModDepthTarget > 5.0) ldModDepthTarget * 0.992 => ldModDepthTarget;

        // Pad LFO (faster in goa for movement)
        0.003 => float padLfoRate;
        if(arrLevel >= 3) padLfoRate * 1.5 => padLfoRate;
        if(phraseBar % 4 == 2) padLfoRate * 1.3 => padLfoRate;
        if(phraseBar >= 12) padLfoRate * 0.7 => padLfoRate;
        padLfoPhase + padLfoRate => padLfoPhase;
        Math.sin(padLfoPhase) * 250.0 => float padLfoMod;
        padF.freq() + ((padFiltTarget + padLfoMod) - padF.freq()) * 0.015 => padF.freq;
        if(padFiltTarget > 400.0) padFiltTarget * 0.9997 => padFiltTarget;
        padG.gain() + (padGainTarget - padG.gain()) * 0.01 => padG.gain;
        if(transition == 4) 0.0 => padGainTarget;

        // FX HPF release
        if(fxType != 1 && !introActive) fxHPF.freq() + (20.0 - fxHPF.freq()) * 0.04 => fxHPF.freq;

        // Master gain
        masterGain + (masterTarget - masterGain) * 0.02 => masterGain;
        masterGain * volume => master.gain;

        thisStepDur / SUBSTEPS => now;
    }

    stepCount + 1 => stepCount;
}
