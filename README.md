# BackTrack

A minimal, rule-based backing-track generator for live solo practice and
performance. Drums and pads only, 4/4 only, keyboard-driven. Native macOS.

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode or Command Line Tools)

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

| Key     | Action                           |
|---------|----------------------------------|
| `Space` | start / stop                     |
| `T`     | tap tempo (4-tap rolling avg)    |
| `↑` `↓` | tempo ± 1 BPM                    |
| `R`     | reload samples from disk         |
| `K`     | kick volume (cycles 100→75→50→25→0→100) |
| `S`     | snare volume                     |
| `H`     | hi-hat volume                    |
| `P`     | pad volume                       |

Queued (commit on beat 1 of the next bar):

| Key     | Action                           |
|---------|----------------------------------|
| `A`–`G` | root note                        |
| `M`     | toggle major / minor             |
| `1` `2` `3` | complexity level             |

Pending changes show next to the current value with an arrow
(`C min → F min`) and disappear the instant they commit.

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

- `App.swift` — entry point, coordinator wiring
- `AppState.swift` — `ObservableObject` with musical + mix state
- `AudioEngine.swift` — AVAudioEngine graph, sample loading, pad pitch shift
- `Clock.swift` — 16th-note timer, tap tempo, transport, pending drain
- `Generators.swift` — pure drum/pad pattern functions
- `KeyboardHandler.swift` — NSEvent local monitor
- `ContentView.swift` — SwiftUI HUD
