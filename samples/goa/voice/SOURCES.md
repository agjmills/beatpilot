# Goa Voice Samples — Sources & Attribution

The goa engine plays voice clips at phrase boundaries and breakdowns. Up to 8
slots: `voice_1.wav` through `voice_8.wav`.

## Included in this repo

| Slot | Clip | Source | License |
|------|------|--------|---------|
| `voice_1.wav` | Apollo 11 launch countdown | [NASA Apollo 11 Highlights](https://archive.org/details/Apollo11AudioHighlights) | Public domain (US gov) |
| `voice_2.wav` | "Hello there sports fans" | [NASA Apollo 11 Highlights](https://archive.org/details/Apollo11AudioHighlights) | Public domain (US gov) |
| `voice_3.wav` | "T-minus 1 minute and counting" | [NASA Apollo 13 Highlights](https://archive.org/details/Apollo13Highlights) | Public domain (US gov) |
| `voice_4.wav` | Albert Hofmann anecdote | [Psychedelic Salon: Tripping With Albert](https://archive.org/details/678-tripping-with-albert) | CC-BY-NC-SA 3.0 ([Psychedelic Salon](https://psychedelicsalon.com)) |

## Slots 5–8 — fetch them yourself

Slots 5–8 use Alan Watts material. The Watts estate is litigious about
redistribution, so we don't ship the clips — but you can grab them in 30 seconds
with the script below. Same workflow we used to build the included clips.

### Source
[Archive.org — Alan Watts Edited](https://archive.org/details/AlanWattsEdited)

### Run this from the repo root

```bash
cd samples/goa/voice

URL="https://archive.org/download/AlanWattsEdited/AlanWattsEdited.mp3"

# voice_5: "the question we have to decide is whether to take life seriously or not"
ffmpeg -y -ss 0    -t 13 -i "$URL" -ac 1 -ar 44100 -sample_fmt s16 voice_5.wav -loglevel error

# voice_6: "looks at humans like a bunch of birds on a barren tree"
ffmpeg -y -ss 89   -t 9  -i "$URL" -ac 1 -ar 44100 -sample_fmt s16 voice_6.wav -loglevel error

# voice_7: "they are inseparably related to their physical environment"
ffmpeg -y -ss 1201 -t 8  -i "$URL" -ac 1 -ar 44100 -sample_fmt s16 voice_7.wav -loglevel error

# voice_8: "the development of technology and centralised government are a direct threat to personality"
ffmpeg -y -ss 1496 -t 14 -i "$URL" -ac 1 -ar 44100 -sample_fmt s16 voice_8.wav -loglevel error
```

Then `/music` (toggle off then on) to reload the engine.

## Adding your own clips

You can replace any slot with your own WAV — Hofmann lectures, sci-fi movies you
own, podcasts, anything. Trim with:

```bash
ffmpeg -ss <start_seconds> -t <length_seconds> -i input.mp3 \
  -ac 1 -ar 44100 -sample_fmt s16 voice_N.wav
```

The engine picks up files at startup. Mono, 44.1kHz, 16-bit WAV is ideal but
ChucK will read most formats.
