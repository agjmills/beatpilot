import type { On } from 'claude-code'
import { describe, expect, mock, test } from 'claude-code/testing'

import { chordName, energyFromRate, parseNow, scaleName, stampOf, stateText, statusText, tuneOf } from './music'

const NOW_TEXT = [
  'genre techno',
  'bpm 128',
  'tick 321',
  'energy 2',
  'key 5',
  'seed 77',
  'scale 0,3,5,7,10',
  'prog 0,4,3,1',
  'chord 1',
  'bar 4',
  'level 3',
  'arr 2,2,3,3,3,3,3,3,2,2,2,2,1,1,2,2',
  'playing 1',
  'volume 80',
  'end',
  '',
].join('\n')

describe('music helpers', () => {
  test('the same text always gives the same tune', async () => {
    expect(tuneOf('add a login page')).toEqual(tuneOf('add a login page'))
    const t = tuneOf('x')
    expect(t.key >= 0 && t.key < 12 && t.scale < 4 && t.seed < 256).toBe(true)
  })

  test('the state file has the five lines the engines read', async () => {
    expect(stateText(5, { key: 1, scale: 2, seed: 3 }, 1234.7)).toBe('3\n1\n2\n3\n1235\n')
  })

  test('the timestamp fits the engines 32-bit atoi and still changes every ms', async () => {
    // A real clock reading: 13 digits wraps negative in ChucK's Std.atoi.
    const now = 1_794_570_052_276
    for (const ms of [now, now + 1, 0, 999_999_999, 2 ** 40]) {
      const stamp = stampOf(ms)
      expect(stamp > 0 && stamp < 2 ** 31).toBe(true)
    }
    expect(stampOf(now + 1)).not.toBe(stampOf(now))
  })

  test('the engine report parses, and a half-written one does not', async () => {
    const now = parseNow(NOW_TEXT)
    expect(now?.genre).toBe('techno')
    expect(now?.arr.length).toBe(16)
    expect(now?.playing).toBe(true)
    expect(parseNow('genre techno\ntick 3\n')).toBe(null)
  })

  test('names scales and chords', async () => {
    expect(scaleName([0, 3, 5, 7, 10])).toBe('minor pentatonic')
    // A natural minor, degree 0 → Am, degree 2 → C, degree 1 → B°
    const minor = [0, 2, 3, 5, 7, 8, 10]
    expect(chordName(9, minor, 0)).toBe('Am')
    expect(chordName(9, minor, 2)).toBe('C')
    expect(chordName(9, minor, 1)).toBe('B°')
    const now = parseNow(NOW_TEXT)
    expect(now === null ? '' : statusText(now)).toBe('♪ techno · F minor pentatonic · ▮▮▯ · bar 5/16')
  })

  test('energy follows how busy the session is', async () => {
    expect(energyFromRate([], 0, 0)).toBe(2)
    expect(energyFromRate(Array.from({ length: 10 }, (_, i) => i * 1000), 10_000, 0)).toBe(3)
    expect(energyFromRate([0], 100_000, 1)).toBe(3)
  })
})

/** The host beneath the plugin: a run directory in memory, ChucK present. */
function host(on: On) {
  const files = new Map<string, string>()
  const clock = mock.clock(on, { now: 1_000_000 })
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', () => ({ value: { command: 'beatpilot' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.status', () => ({ value: undefined }))
  on('fs.write', (_, e) => {
    files.set(e.path, e.text)
    return { value: undefined }
  })
  on('fs.exists', (_, e) => ({ value: files.has(e.path) }))
  on('fs.read', (_, e) => {
    const text = files.get(e.path)
    if (text === undefined) throw new Error('ENOENT')
    return { value: text }
  })
  on('process.run', (_, e) => {
    const [cmd, , a, b] = e.argv
    if (cmd === 'bash') return { value: { exitCode: 0, stdout: '/run/bp\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    if (cmd === 'rm' && a !== undefined) files.delete(a)
    if (cmd === 'mv' && a !== undefined && b !== undefined) {
      files.set(b, files.get(a) ?? '')
      files.delete(a)
    }
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.log', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('process.spawn', async function* () {
    yield* []
    return { value: { code: 0, signal: null } }
  })
  return { files, clock }
}

const energyOf = (files: Map<string, string>): string | undefined => files.get('/run/bp/state')?.split('\n')[0]

test('activity writes the state the engines read; a failed tool call is tension, not silence', async ($, on) => {
  const { files, clock } = host(on)
  on('tool.call', (_, e) => (e.tool === 'Bash' && e.command === 'false' ? { result: {}, isError: true } : { result: {} }))

  await $.session.start({ cwd: '/work/app', surface: 'terminal', isInteractive: true })
  expect(files.get('/run/bp/genre')).toBe('techno\n')

  await $.tool.call({ tool: 'Read', file_path: '/work/app/a.ts' })
  await clock.advance(1000)
  expect(energyOf(files)).toBe('2')

  await $.tool.call({ tool: 'Bash', command: 'false' })
  await clock.advance(1000)
  expect(energyOf(files)).toBe('1')
})

test('a tool call keeps the tune; a new prompt changes it', async ($, on) => {
  const { files, clock } = host(on)
  on('tool.call', () => ({ result: {} }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  const tuneLines = (): string => (files.get('/run/bp/state') ?? '').split('\n').slice(1, 4).join(',')

  await $.session.start({ cwd: '/work/app', surface: 'terminal', isInteractive: true })
  await $.tool.call({ tool: 'Read', file_path: '/a' })
  await clock.advance(1000)
  const first = tuneLines()
  await $.tool.call({ tool: 'Bash', command: 'ls' })
  await clock.advance(1000)
  expect(tuneLines()).toBe(first)

  const t = tuneOf('fix the flaky test')
  await $.prompt.submit({ text: 'fix the flaky test', wait: false, origin: { kind: 'composer' } })
  await clock.advance(1000)
  expect(tuneLines()).toBe(`${t.key},${t.scale},${t.seed}`)
})

test('a headless session plays nothing', async ($, on) => {
  const { files } = host(on)
  await $.session.start({ cwd: '/w', surface: null, isInteractive: false })
  expect(files.size).toBe(0)
})

const PANE = {
  plugin: 'beatpilot',
  component: 'Pane',
  requestId: 'beatpilot',
  props: {
    title: 'Beatpilot',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const

test('the player shows what the engine reports, on every surface', async ($, on) => {
  const { files, clock } = host(on)
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  files.set('/run/bp/now', NOW_TEXT)
  await clock.advance(1100)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Text', text: /♪ techno/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /F minor pentatonic/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /bar 5\/16/ })).toBeDefined()
    await ui.unmount()
  }
})

test('before any music the player says it is waiting', async ($, on) => {
  host(on)
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /Waiting for activity/ })).toBeDefined()
  await ui.unmount()
})

const BAND = {
  plugin: 'beatpilot',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isCollapsed: false,
    isWorking: false,
    maxRows: 4,
    bodyColumns: 80,
    scroll: { offset: 0, bodyRows: 4 },
    view: {},
  },
} as const

test('the play bar pauses and resumes the music, on every surface', async ($, on) => {
  const { files, clock } = host(on)
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  files.set('/run/bp/now', NOW_TEXT)
  await clock.advance(1100)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ key: 'play-pause' }))?.text).toMatch(/pause/)
    await ui.press({ key: 'play-pause' })
    expect(files.has('/run/bp/disabled')).toBe(true)
    expect((await ui.find({ key: 'play-pause' }))?.text).toMatch(/play/)
    expect(await ui.find({ type: 'Text', text: /paused/ })).toBeDefined()

    await ui.press({ key: 'play-pause' })
    expect(files.has('/run/bp/disabled')).toBe(false)
    await ui.unmount()
    files.set('/run/bp/now', NOW_TEXT.replace('tick 321', `tick ${400 + surface.length}`))
    await clock.advance(1100)
  }
})

test('the play bar stays out of the way before any music', async ($, on) => {
  host(on)
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect(await ui.find({ key: 'play-pause' })).toBeUndefined()
  await ui.unmount()
})
