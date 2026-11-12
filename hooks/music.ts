// Pure helpers: hashing, parsing the engine's report, naming notes and scales.
// No `$` here, so the tests can exercise them directly.

import type { NowPlaying } from '../types'

export const GENRES = ['techno', 'dnb', 'lofi', 'reggae', 'dub', 'goa', 'piano', 'ambient'] as const
export type Genre = (typeof GENRES)[number]

export const isGenre = (value: string): value is Genre => (GENRES as readonly string[]).includes(value)

export type Tune = { key: number; scale: number; seed: number }

/** FNV-1a, 32-bit: the same text always gives the same tune. */
export function hash(text: string): number {
  let h = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i)
    h = Math.imul(h, 0x01000193) >>> 0
  }
  return h >>> 0
}

export function tuneOf(text: string): Tune {
  const h = hash(text)
  return { key: h % 12, scale: Math.floor(h / 12) % 4, seed: Math.floor(h / 48) % 256 }
}

/** The state file the engines read: energy, key, scale, seed, timestamp. */
export function stateText(energy: number, tune: Tune, ts: number): string {
  const e = Math.max(0, Math.min(3, Math.round(energy)))
  return `${e}\n${tune.key}\n${tune.scale}\n${tune.seed}\n${Math.floor(ts)}\n`
}

const ints = (text: string | undefined): number[] =>
  (text ?? '')
    .split(',')
    .filter(part => part.trim() !== '')
    .map(part => Number.parseInt(part, 10))
    .filter(Number.isFinite)

/** Parses <run dir>/now; null while it is missing or half-written. */
export function parseNow(text: string): NowPlaying | null {
  const fields = new Map<string, string>()
  const lines = text.split('\n')
  if (!lines.includes('end')) return null
  for (const line of lines) {
    const at = line.indexOf(' ')
    if (at > 0) fields.set(line.slice(0, at), line.slice(at + 1).trim())
  }
  const num = (name: string): number => Number.parseInt(fields.get(name) ?? '', 10)
  const tick = num('tick')
  if (!Number.isFinite(tick) || !fields.has('genre')) return null
  return {
    genre: fields.get('genre') ?? '',
    bpm: num('bpm'),
    tick,
    energy: num('energy'),
    key: num('key'),
    seed: num('seed'),
    scale: ints(fields.get('scale')),
    prog: ints(fields.get('prog')),
    chord: num('chord'),
    bar: num('bar'),
    level: num('level'),
    arr: ints(fields.get('arr')),
    playing: fields.get('playing') === '1',
    volume: num('volume'),
  }
}

export const NOTE_NAMES = ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B']

const SCALE_NAMES: Record<string, string> = {
  '0,2,4,7,9': 'major pentatonic',
  '0,3,5,7,10': 'minor pentatonic',
  '0,2,4,5,7,9,11': 'major',
  '0,2,3,5,7,8,10': 'natural minor',
  '0,2,3,5,7,8,11': 'harmonic minor',
  '0,2,3,5,7,9,10': 'dorian',
  '0,1,3,5,7,8,10': 'phrygian',
  '0,2,4,6,7,9,11': 'lydian',
  '0,2,4,5,7,9,10': 'mixolydian',
  '0,1,3,4,6,7,9,10': 'diminished',
  '0,2,4,7,11': 'major 7',
  '0,2,3,5,9': 'dorian (5-note)',
  '0,2,4,6,7': 'lydian (5-note)',
  '0,2,4,5,7': 'major (5-note)',
  '0,2,3,7,10': 'minor (5-note)',
  '0,1,3,7,10': 'phrygian (5-note)',
  '0,1,4,7,8': 'phrygian dominant (5-note)',
  '0,3,7,8,11': 'harmonic minor (5-note)',
  '0,1,4,7,10': 'phrygian dominant',
}

export function scaleName(intervals: readonly number[]): string {
  return SCALE_NAMES[intervals.join(',')] ?? 'mode'
}

/** The chord built on a scale degree: its root name, and m/° on 7-note scales. */
export function chordName(key: number, scale: readonly number[], degree: number): string {
  if (scale.length === 0) return '?'
  const len = scale.length
  const at = (d: number): number => (scale[((d % len) + len) % len] ?? 0) + 12 * Math.floor(d / len)
  const root = at(degree)
  let quality = ''
  if (len === 7) {
    const third = at(degree + 2) - root
    const fifth = at(degree + 4) - root
    quality = third === 3 ? (fifth === 6 ? '°' : 'm') : ''
  }
  return (NOTE_NAMES[(((key + root) % 12) + 12) % 12] ?? '?') + quality
}

const BLOCKS = ['▁', '▃', '▅', '▇']
export const levelBlock = (level: number): string => BLOCKS[Math.max(0, Math.min(3, level))] ?? '▁'

export function energyMeter(energy: number): string {
  const e = Math.max(0, Math.min(3, energy))
  return '▮'.repeat(e) + '▯'.repeat(3 - e)
}

export const ENERGY_WORDS = ['resting', 'calm', 'active', 'intense']

/** The status-line text for what is playing. */
export function statusText(now: NowPlaying): string {
  if (!now.playing) return `♪ ${now.genre} · resting`
  const key = NOTE_NAMES[((now.key % 12) + 12) % 12] ?? '?'
  return `♪ ${now.genre} · ${key} ${scaleName(now.scale)} · ${energyMeter(now.energy)} · bar ${now.bar + 1}/16`
}

/** Rate-based energy: how busy the session has been over the last 30 s. */
export function energyFromRate(callTimes: readonly number[], at: number, agents: number): number {
  if (agents > 0) return 3
  const recent = callTimes.filter(t => at - t < 30_000).length
  return recent >= 10 ? 3 : 2
}
