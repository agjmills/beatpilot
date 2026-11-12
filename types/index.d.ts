/** What the engine reports once per bar in <run dir>/now. */
export type NowPlaying = {
  genre: string
  bpm: number
  /** The engine's step counter: changes each bar while it runs. */
  tick: number
  energy: number
  key: number
  seed: number
  /** Scale intervals in semitones from the key. */
  scale: number[]
  /** The 4-chord progression as scale degrees. */
  prog: number[]
  /** Which of the 4 chords is sounding (0-3). */
  chord: number
  /** Bar within the 16-bar phrase (0-15). */
  bar: number
  /** Arrangement level of this bar (0 minimal … 3 bass+pad+lead). */
  level: number
  /** Arrangement level of every bar of the phrase. */
  arr: number[]
  /** False while the engine has faded to silence. */
  playing: boolean
  volume: number
}

/**
 * idle: no engine yet this session; starting: spawned, no bar reported yet;
 * live: an engine (ours or another session's) is reporting bars; off: paused
 * by the person; missing: ChucK is not installed; headless: a -p/SDK session.
 */
export type EngineStatus = 'idle' | 'starting' | 'live' | 'off' | 'missing' | 'headless'

declare module 'claude-code' {
  interface PluginState {
    beatpilot: {
      now: NowPlaying | null
      status: EngineStatus
      bandHidden: boolean
    }
  }
}
