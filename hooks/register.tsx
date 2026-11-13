// Beatpilot for Claude Code: the in-process side of the plugin.
//
// Replaces the shell hooks for plugin installs. It turns session activity
// into the state file the ChucK engines read, owns the engine process for the
// session's life, and shows what is playing: a status line, a /beatpilot pane
// and an optional band above the prompt. The shell adapters (Copilot CLI, the
// file watcher, ./install.sh) keep working unchanged against the same files.

import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { EngineStatus } from '../types'
import {
  ENERGY_WORDS,
  GENRES,
  NOTE_NAMES,
  chordName,
  energyFromRate,
  energyMeter,
  isGenre,
  levelBlock,
  parseNow,
  scaleName,
  stateText,
  statusText,
  tuneOf,
} from './music'
import type { Genre, Tune } from './music'

const PANE = 'beatpilot'
const nowAtom = atom({ plugin: 'beatpilot', key: 'now' } as const, null)
const statusAtom = atom({ plugin: 'beatpilot', key: 'status' } as const, 'idle')
const bandHiddenAtom = atom({ plugin: 'beatpilot', key: 'bandHidden' } as const, false)

const POLL_MS = 1000
/** No new bar for this long means no engine (a 60 bpm bar is 4 s). */
const STALE_MS = 10_000
const WRITE_GAP_MS = 250

/** What session.start builds once the session is ready; the other hooks call it. */
type Player = {
  writeState: () => Promise<void>
  pause: () => Promise<string>
  resume: () => Promise<string>
  setVolume: (volume: number) => Promise<string>
  volume: () => Promise<number>
  newTune: () => Promise<string>
  chooseGenre: (genre: string) => Promise<string>
}

export const register: Register = (on, options) => {
  const genre: Genre = isGenre(String(options.genre ?? '')) ? (options.genre as Genre) : 'techno'
  const showStatus = options.statusLine !== false
  const showBand = options.band === true
  const inHeadless = options.headless === true
  const newTunePerPrompt = options.tunePerPrompt !== false

  // Module state starts over on a reload; the engine's report and the atoms
  // ($.state) carry what matters across.
  let player: Player | null = null
  let tune: Tune = { key: 0, scale: 0, seed: 0 }
  let energy = 2
  let agents = 0
  let callTimes: number[] = []

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    if (!e.isInteractive && !inHeadless) {
      await update($, statusAtom, () => 'headless')
      return started
    }
    const root = $.plugin.root
    const printed = await $.process.run(['bash', `${root}/lib/paths.sh`, '--print'])
    const run = printed.stdout.trim()
    if (printed.exitCode !== 0 || run === '') {
      $.ui.log(`beatpilot: no runtime directory: ${printed.stderr.trim()}`, { to: 'debug' })
      return started
    }
    const path = (name: string): string => `${run}/${name}`
    const env = { CLAUDE_PLUGIN_ROOT: root }

    let lastTick = -1
    let lastTickAt = 0
    let spawnedAt = -Infinity
    let owning = false
    let lastWriteAt = 0
    let writeQueued = false
    let lastGenre = ''

    const sh = async (argv: string[]): Promise<number> => {
      try {
        return (await $.process.run(argv, { env, timeoutMs: 15_000 })).exitCode
      } catch {
        return 127
      }
    }
    const isDisabled = (): Promise<boolean> => $.fs.exists(path('disabled'))
    const isLive = async (): Promise<boolean> =>
      lastTick >= 0 && (await $.clock.now()) - lastTickAt < STALE_MS

    const setStatus = async (status: EngineStatus): Promise<void> => {
      await update($, statusAtom, () => status)
      if (!showStatus) return
      if (status === 'off') $.ui.status('♪ paused')
      else if (status === 'missing') $.ui.status('♪ ChucK not installed')
      else if (status === 'starting') $.ui.status('♪ starting…')
      else if (status !== 'live') $.ui.status(undefined)
    }

    /** Starts an engine owned by this session unless one is already running. */
    const ensureEngine = async (): Promise<void> => {
      if (owning || (await isDisabled()) || (await isLive())) return
      const at = await $.clock.now()
      if (at - spawnedAt < STALE_MS) return
      spawnedAt = at
      if ((await sh(['sh', '-c', 'command -v chuck'])) !== 0) {
        await setStatus('missing')
        $.ui.toast('Beatpilot: ChucK is not installed (brew install chuck / sudo apt install chuck)')
        return
      }
      await setStatus('starting')
      owning = true
      void (async () => {
        // start.sh --foreground takes the lock, clears stale engines, then
        // becomes the engine: the loop ending (or the session) kills it. With
        // another session's engine already up it just exits.
        try {
          const child = $.process.spawn({ argv: [`${root}/start.sh`, '--foreground'], env })
          for await (const { text } of child) $.ui.log(text.trimEnd(), { to: 'debug' })
        } catch (error) {
          $.ui.log(`beatpilot: engine did not start: ${String(error)}`, { to: 'debug' })
        } finally {
          owning = false
        }
      })()
    }

    const restartEngine = async (): Promise<void> => {
      await sh([`${root}/stop.sh`])
      lastTick = -1
      spawnedAt = -Infinity
      owning = false
      await ensureEngine()
    }

    /** Writes the state file at most every WRITE_GAP_MS; a burst ends in one last write. */
    const writeState = async (): Promise<void> => {
      if (await isDisabled()) return
      const at = await $.clock.now()
      if (at - lastWriteAt < WRITE_GAP_MS) {
        if (!writeQueued) {
          writeQueued = true
          $.clock.after(WRITE_GAP_MS, () => {
            writeQueued = false
            void writeState()
          })
        }
        return
      }
      lastWriteAt = at
      const tmp = path(`state.${Math.floor(at)}`)
      await $.fs.write(tmp, stateText(energy, tune, at))
      await sh(['mv', '-f', tmp, path('state')])
      await ensureEngine()
    }

    const poll = async (): Promise<void> => {
      let text = ''
      try {
        text = await $.fs.read(path('now'))
      } catch {
        text = ''
      }
      const now = parseNow(text)
      const at = await $.clock.now()
      if (now !== null && now.tick !== lastTick) {
        lastTick = now.tick
        lastTickAt = at
        await update($, nowAtom, () => now)
        if ((await read($, statusAtom)) !== 'live') await update($, statusAtom, () => 'live')
        if (showStatus) $.ui.status(statusText(now))
        if (lastGenre !== '' && now.genre !== lastGenre) $.ui.toast(`Beatpilot → ${now.genre}`)
        lastGenre = now.genre
      } else if (lastTick >= 0 && at - lastTickAt >= STALE_MS) {
        lastTick = -1
        await update($, nowAtom, () => null)
        await setStatus((await isDisabled()) ? 'off' : 'idle')
      }
    }

    const volume = async (): Promise<number> => {
      const now = await read($, nowAtom)
      if (now !== null && Number.isFinite(now.volume)) return now.volume
      const stored = await $.store.get('volume')
      return typeof stored === 'number' ? stored : 80
    }

    const setVolume = async (wanted: number): Promise<string> => {
      const v = Math.max(0, Math.min(100, Math.round(wanted)))
      await $.fs.write(path('volume'), `${v}\n`)
      await $.store.set('volume', v)
      const now = await read($, nowAtom)
      if (now !== null) await update($, nowAtom, () => ({ ...now, volume: v }))
      return `Beatpilot volume ${v}%.`
    }

    player = {
      writeState,
      volume,
      setVolume,
      pause: async () => {
        await $.fs.write(path('disabled'), '')
        await sh([`${root}/stop.sh`])
        await update($, nowAtom, () => null)
        await setStatus('off')
        return 'Beatpilot paused.'
      },
      resume: async () => {
        await sh(['rm', '-f', path('disabled')])
        spawnedAt = -Infinity
        energy = 2
        await setStatus('idle')
        await writeState()
        return 'Beatpilot playing.'
      },
      newTune: async () => {
        tune = tuneOf(`${Math.random()}`)
        await writeState()
        return 'New tune from the next phrase.'
      },
      // Through the plugin's setting, so /config, the pane and the command agree.
      chooseGenre: async (wanted: string) => {
        if (!isGenre(wanted)) return `Unknown genre: ${wanted}. Pick one of ${GENRES.join(', ')}.`
        const row = (await $.config.list()).find(r => /^beatpilot[^.]*\.genre$/.test(r.key))
        if (row !== undefined) {
          const { deny } = await $.config.set({ key: row.key, value: wanted })
          if (deny === undefined) return `Switching to ${wanted}.` // the reload applies it
        }
        await $.fs.write(path('genre'), `${wanted}\n`)
        await restartEngine()
        return `Switching to ${wanted}.`
      },
    }

    tune = tuneOf(e.cwd) // the project's tune until the first prompt

    await $.command.register({
      name: 'beatpilot',
      description: 'Beatpilot: open the player, or on | off | <genre> | vol <0-100> | new',
      argumentHint: '[on|off|<genre>|vol N|new]',
    })

    const storedVolume = await $.store.get('volume')
    if (typeof storedVolume === 'number') await $.fs.write(path('volume'), `${storedVolume}\n`)

    // Apply the genre setting when it changed (this load is the reload it caused).
    const applied = await $.store.get('genre')
    const hasGenreFile = await $.fs.exists(path('genre'))
    if (applied !== genre || !hasGenreFile) {
      await $.fs.write(path('genre'), `${genre}\n`)
      await $.store.set('genre', genre)
    }

    // A reload kills the engine this session owned: bring it back if music was on.
    const before = await read($, nowAtom)
    if (await isDisabled()) await setStatus('off')
    else if (before !== null && before.genre !== genre) await restartEngine()
    else if (before !== null) await ensureEngine()

    $.clock.every(POLL_MS, () => void poll())
    return started
  })

  on('command.run', { command: 'beatpilot' }, async ($, e) => {
    if (player === null) return { text: 'Beatpilot is inactive in this session (headless, or no runtime directory).' }
    const [word = '', arg = ''] = e.args.trim().toLowerCase().split(/\s+/)
    if (word === '') {
      await $.ui.open({ id: PANE, title: 'Beatpilot' })
      return { text: 'Beatpilot player opened.' }
    }
    if (word === 'off' || word === 'pause' || word === 'stop') return { text: await player.pause() }
    if (word === 'on' || word === 'play' || word === 'resume') return { text: await player.resume() }
    if (word === 'new') return { text: await player.newTune() }
    if (word === 'vol' || word === 'volume') {
      const v = Number.parseInt(arg, 10)
      return { text: Number.isFinite(v) ? await player.setVolume(v) : `Volume ${await player.volume()}%.` }
    }
    return { text: await player.chooseGenre(word) }
  })

  // ---- Activity → music ----

  on('prompt.submit', async ($, e, next) => {
    const result = await next(e)
    if (player !== null) {
      // A new task gets a new tune; the engine brings it in at the next phrase.
      if (newTunePerPrompt && e.text.trim() !== '') tune = tuneOf(e.text)
      energy = Math.max(2, energyFromRate(callTimes, await $.clock.now(), agents))
      await player.writeState()
    }
    return result
  })

  on('tool.call', async ($, e, next) => {
    if (player === null) return next(e)
    const isAgent = e.tool === 'Agent'
    const at = await $.clock.now()
    callTimes = [...callTimes.filter(t => at - t < 60_000), at].slice(-50)
    if (isAgent) agents += 1
    energy = energyFromRate(callTimes, at, agents)
    void player.writeState()
    try {
      const ran = await next(e)
      if (ran.deny === undefined && ran.isError === true) {
        // Agents fail tool calls all the time: tension, one level down, not silence.
        energy = Math.max(1, energy - 1)
        void player?.writeState()
      }
      return ran
    } finally {
      if (isAgent) agents = Math.max(0, agents - 1)
    }
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (player !== null && agents === 0) {
      energy = 1 // the engine winds down on its own from here
      await player.writeState()
    }
    return result
  })

  // ---- Drawing ----

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Select } = $.ui.resolve(e)
    const now = await read($, nowAtom)
    const status = await read($, statusAtom)
    const volume = player === null ? 80 : await player.volume()
    const isOff = status === 'off'
    const message =
      status === 'off'
        ? 'Paused.'
        : status === 'missing'
          ? 'ChucK is not installed: brew install chuck / sudo apt install chuck'
          : status === 'starting'
            ? 'Starting the engine…'
            : status === 'headless'
              ? 'Inactive in headless sessions (see the headless setting).'
              : 'Waiting for activity: the music starts when Claude does.'

    return (
      <Box flexDirection="column" gap={1}>
        {now === null ? (
          <Text dimColor>{message}</Text>
        ) : (
          <Box flexDirection="column">
            <Text>
              <Text bold>♪ {now.genre}</Text>
              <Text dimColor>
                {'  '}
                {now.bpm} bpm · {NOTE_NAMES[((now.key % 12) + 12) % 12]} {scaleName(now.scale)} ·{' '}
                {now.playing ? 'playing' : 'resting'}
              </Text>
            </Text>
            <Text>
              <Text dimColor>energy </Text>
              {energyMeter(now.energy)} <Text dimColor>{ENERGY_WORDS[now.energy] ?? ''}</Text>
            </Text>
            <Text>
              <Text dimColor>phrase </Text>
              {now.arr.map((level, i) =>
                i === now.bar ? (
                  <Text inverse>{levelBlock(level)}</Text>
                ) : (
                  <Text dimColor={i > now.bar}>{levelBlock(level)}</Text>
                ),
              )}
              <Text dimColor> bar {now.bar + 1}/16</Text>
            </Text>
            <Text>
              <Text dimColor>chords </Text>
              {now.prog.map((degree, i) => (
                <Text bold={i === now.chord} dimColor={i !== now.chord}>
                  {chordName(now.key, now.scale, degree)}
                  {i < now.prog.length - 1 ? '  ' : ''}
                </Text>
              ))}
            </Text>
            <Text>
              <Text dimColor>layers </Text>
              {(['bass', 'pad', 'lead'] as const).map((name, i) => (
                <Text dimColor={now.level < i + 1}>
                  {now.level >= i + 1 ? '●' : '○'} {name}
                  {'  '}
                </Text>
              ))}
            </Text>
          </Box>
        )}
        <Select
          key="genre"
          label="genre "
          value={genre}
          options={GENRES.map(g => ({ value: g, label: g }))}
          onSelect={value => void player?.chooseGenre(value)}
        />
        <Box gap={1}>
          <Button key="vol-down" label="vol −" onPress={() => void player?.setVolume(volume - 10)} />
          <Text>{volume}%</Text>
          <Button key="vol-up" label="vol +" onPress={() => void player?.setVolume(volume + 10)} />
          <Button
            key="pause"
            hotkey="p"
            label={isOff ? 'play' : 'pause'}
            onPress={() => void (isOff ? player?.resume() : player?.pause())}
          />
          <Button key="new" hotkey="n" label="new tune" onPress={() => void player?.newTune()} />
        </Box>
      </Box>
    )
  })

  // The play bar above the prompt: what's playing plus pause/play, so the
  // music can be stopped with one click (or ctrl+x tab, then p) mid-session.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (!showBand || player === null || e.props.hasSurvey || (await read($, bandHiddenAtom))) return next(e)
    const status = await read($, statusAtom)
    const now = await read($, nowAtom)
    const isOff = status === 'off'
    if (!isOff && status !== 'starting' && now === null) return next(e)
    const { Box, Text, Button } = $.ui.resolve(e)
    const toggle = (
      <Button
        key="play-pause"
        hotkey="p"
        label={isOff ? '▶ play' : '⏸ pause'}
        onPress={() => void (isOff ? player?.resume() : player?.pause())}
      />
    )
    return (
      <Box gap={1}>
        {isOff || now === null ? (
          <Text dimColor>♪ {isOff ? 'paused' : 'starting…'}</Text>
        ) : now.playing ? (
          <Text>
            <Text dimColor>♪ {now.genre} </Text>
            {now.arr.map((level, i) =>
              i === now.bar ? <Text inverse>{levelBlock(level)}</Text> : <Text dimColor>{levelBlock(level)}</Text>,
            )}
            <Text dimColor> {energyMeter(now.energy)}</Text>
          </Text>
        ) : (
          <Text dimColor>♪ {now.genre} · resting</Text>
        )}
        {status === 'starting' && now === null ? null : toggle}
        <Button key="hide" label="hide" onPress={() => void update($, bandHiddenAtom, () => true)} />
      </Box>
    )
  })
}
