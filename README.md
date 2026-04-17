# BackTrack

A minimal, rule-based backing-track generator for live solo practice and
performance. Drums and pads only, 4/4 only, keyboard-driven. Native macOS.

Includes real-time pitch detection from the microphone, with an optional
"follow" mode that drives pad chord changes from what you sing or play.

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode or Command Line Tools)
- Microphone access (for pitch detection — the first run will prompt)
- Headphones strongly recommended when using follow mode, to avoid the
  pad output feeding back into the input and confusing detection

## Samples

BackTrack loads user-supplied samples from a fixed directory:

```
~/BackTrack/Samples/
├── drums/
│   ├── kick.{wav|aif|aiff|mp3}
│   ├── snare.{wav|aif|aiff|mp3}
│   └── hh.{wav|aif|aiff|mp3}
└── pads/
    └── pad_<NOTE>.{wav|aif|aiff|mp3}
```

The pad filename encodes the sample's pitch class:

- `pad_C.aif` — sample recorded at C
- `pad_F#.wav` — F-sharp
- `pad_Bb.mp3` — B-flat

Case-insensitive. A trailing octave digit (`pad_C3.aif`) is tolerated but
ignored — pitch shifting is relative to the sample's recorded register, so
the octave you record at determines the chord's natural range.

Missing samples appear in the HUD under `MISSING SAMPLES`. Press `R` to
reload from disk without restarting.

## Run

```
swift run
```

Or build once and launch the binary directly:

```
swift build -c release
./.build/release/BackTrack
```

## Keybindings

Immediate:

| Key     | Action                                   |
|---------|------------------------------------------|
| `Space` | start / stop                             |
| `T`     | tap tempo (4-tap rolling avg)            |
| `↑` `↓` | tempo ± 1 BPM                            |
| `R`     | reload samples + refresh device readout  |
| `L`     | toggle follow mode (pad tracks detected pitch) |
| `K`     | kick volume (cycles 100 → 75 → 50 → 0 → 100) |
| `S`     | snare volume                             |
| `H`     | hi-hat volume                            |
| `P`     | pad volume                               |

Queued (commit on beat 1 of the next bar):

| Key     | Action                           |
|---------|----------------------------------|
| `A`–`G` | root note                        |
| `M`     | toggle major / minor             |
| `1` `2` `3` | complexity level             |

Pending changes show next to the current value with an arrow
(`C min → F min`) and disappear the instant they commit.

## HUD

Three visual groups, top to bottom: global musical state, per-instrument mix,
bar position + transport. Audio routing sits in the upper right.

**Upper block — global state**

| Readout | Meaning |
|---------|---------|
| `KEY` | The tonal center you declared. Updates only on your keystroke; never driven by detection. A dim `(follow)` suffix appears here while follow mode is on. |
| `CHORD` | The chord the pad is currently playing. In manual mode it mirrors `KEY`; in follow mode it diverges per the detected pitch. Pending changes commit on the next bar. |
| `BPM` | Current tempo |
| `COMPLEXITY` | Current complexity (1–3) |
| `DETECTED` | Pitch detected from the microphone (or `—`) |

**Mix block — one row per instrument** (`KICK`, `SNARE`, `HH`, `PAD`)

Each row: an activity light on the left that pulses on trigger and decays over
~180 ms, then the name, then a level meter (0 / 50 / 75 / 100%).

**Transport block**

| Readout | Meaning |
|---------|---------|
| `BEAT / BAR` | Four dots illuminated in sequence as the bar progresses |
| `● PLAYING` / `○ STOPPED` | Transport state, prominent |

**Upper right**

| Readout | Meaning |
|---------|---------|
| `MIC` | System default input device |
| `OUT` | System default output device |

## Pitch detection

Runs continuously on a dedicated input-only `AVAudioEngine`, isolated from
the playback engine. Uses the YIN algorithm (de Cheveigné & Kawahara, 2002)
with a cumulative mean normalized difference function and parabolic
interpolation for sub-sample accuracy. An RMS silence gate suppresses noise,
and the last detected note is held for ~400 ms to avoid flicker between
breaths or consonants.

## Key vs. chord

BackTrack distinguishes two things:

- **KEY** — the tonal center you declare. Updates the instant you press
  `A`–`G` or `M`. Nothing else changes it — detection never touches the
  key. A dim `(follow)` suffix appears next to `KEY` in the HUD while
  follow mode is on, as the only mode indicator.
- **CHD** — the chord the pad is currently playing. Queued to the next
  bar boundary (shows a `→` pending arrow while it's about to change).
  In manual mode it mirrors `KEY`. In follow mode it's driven by the
  diatonic snap from detection.

Pressing `A`–`G` or `M` updates `KEY` immediately and queues the matching
chord change — so in manual mode you'll see `KEY` flash to the new value
on keypress while `CHD` shows the pending arrow until the next bar.

## Follow mode

When `L` is toggled on, each detected pitch is mapped to the nearest
diatonic scale degree in the current `KEY`, and the corresponding chord
(major or minor per the scale) is queued as a pending `CHD` change —
committing cleanly on the next bar like any other pending change. `KEY`
itself does not move. To re-key mid-song, press `A`–`G` / `M` as usual;
`KEY` updates immediately and detection starts snapping against the new
key from the next buffer on.

## Generators

Patterns are pure functions of `(state, tick)`. Complexity is global across
both instruments.

**Drums**

| LVL | Pattern |
|-----|---------|
| 1 | Kick 1&3, snare 2&4, hi-hat quarters |
| 2 | Kick 1&3, snare 2&4, hi-hat 8ths |
| 3 | Kick 1, 3, and-of-3; snare 2&4 + e-of-4 ghost; hi-hat 16ths |

**Pads**

| LVL | Pattern |
|-----|---------|
| 1 | Sustained root + fifth, full bar |
| 2 | Full triad (major/minor), gated on 8ths |
| 3 | Extended chord (triad + 7th, 9th), arpeggiated on 8ths |

## Files

- `App.swift` — entry point, coordinator wiring, device bootstrap
- `AppState.swift` — `ObservableObject` with musical, mix, detection, and routing state
- `AudioEngine.swift` — playback `AVAudioEngine`, per-instrument mixer buses, sample loading, pad pitch shift
- `AudioDevices.swift` — CoreAudio helpers for default input/output device names
- `Clock.swift` — 16th-note timer, tap tempo, transport, pending drain
- `Generators.swift` — pure drum/pad pattern functions
- `KeyboardHandler.swift` — NSEvent local monitor
- `PitchDetector.swift` — dedicated input `AVAudioEngine`, YIN pitch detection, diatonic snap for follow mode
- `ContentView.swift` — SwiftUI HUD
