# BackTrack

A minimal, rule-based backing-track generator for live solo practice and
performance. Rule-based drums on a 4/4 grid plus a live pad effect that
responds directly to whatever you're singing or playing into the mic.
Keyboard-driven. Native macOS.

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode or Command Line Tools)
- Microphone access (for the live pad effect and pitch detection — the
  first run will prompt)
- Headphones or a routed monitor setup so the pad output doesn't feed
  back into the input

## Samples

BackTrack loads drum samples from a fixed directory:

```
~/BackTrack/Samples/
└── drums/
    ├── kick.{wav|aif|aiff|mp3}
    ├── snare.{wav|aif|aiff|mp3}
    └── hh.{wav|aif|aiff|mp3}
```

Missing samples appear in the HUD under `MISSING SAMPLES`. Press `R` to
reload from disk without restarting. There are no pad samples — the pad
is generated live from your mic input.

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
| `Space` | start / stop drums                       |
| `T`     | tap tempo (4-tap rolling avg)            |
| `↑` `↓` | tempo ± 1 BPM                            |
| `R`     | reload samples + refresh device readout  |
| `K`     | kick volume (cycles 100 → 75 → 50 → 0 → 100) |
| `S`     | snare volume                             |
| `H`     | hi-hat volume                            |
| `P`     | cycle pad mode (OFF → SIMPLE → SHIMMER → SYNTH → STRINGS → OFF) |

Queued (commit on beat 1 of the next bar):

| Key     | Action                           |
|---------|----------------------------------|
| `1` `2` `3` | complexity level             |

## HUD

Three groups, top to bottom.

**Upper block — global state**

| Readout | Meaning |
|---------|---------|
| `BPM` | Current tempo |
| `COMPLEXITY` | Current complexity (1–3) |
| `DETECTED` | Pitch detected from the microphone (or `—`) — display only, doesn't drive anything |

**Mix block — one row per instrument**

| Row | Behavior |
|-----|----------|
| `KICK` / `SNARE` / `HH` | Activity light on the left pulses on each trigger and decays over ~180 ms; then the name; then a level meter (0 / 50 / 75 / 100%) |
| `PAD` | Live effect chain. Activity light tracks mic signal; row displays the current pad mode (OFF / SIMPLE / SHIMMER / SYNTH / STRINGS) instead of a meter |

**Transport block**

| Readout | Meaning |
|---------|---------|
| `BEAT / BAR` | Four dots illuminated in sequence as the bar progresses |
| `● PLAYING` / `○ STOPPED` | Drum transport state |

**Upper right**

| Readout | Meaning |
|---------|---------|
| `MIC` | System default input device, with a small activity dot that lights when the mic has audible signal |
| `OUT` | System default output device, with a small activity dot that lights whenever anything is leaving the output bus |

## Pad effect

The pad is a live processing chain on the mic input. Buffers are
captured on the input engine's tap and forwarded into a player node
in the output engine, which runs them through three parallel paths
(dry, +12 pitch shift, −12 pitch shift) into a pre-reverb mixer, then
through a reverb and the pad mixer:

```
input → tap → liveInputPlayer → [ dry (EQ) | +12 | −12 ]
                               → preReverbMixer → reverb → padMixer → out
```

Because it's a direct effect rather than a sample trigger, it tracks
everything you play with essentially zero interpretive latency: strum a
chord and you hear a reverbed swell of that exact chord; finger-pick a
pattern and the arpeggio blurs into a soft wash.

The `P` key cycles through five modes. Each mode is a preset: the gains
on the three parallel paths, the EQ's filter + frequency, and the
reverb preset + wet mix. Topology stays constant.

| Mode | Character |
|------|-----------|
| `OFF` | Pad mixer muted; no live effect output |
| `SIMPLE` | High-pass at 100 Hz, large hall reverb 85% wet. Dry baseline. |
| `SHIMMER` | Dry + +12 octave layer, cathedral reverb 95% wet, gentle high-pass. Classic octave-up shimmer. |
| `SYNTH` | Low-pass at 2 kHz + −12 sub-octave layer + cathedral reverb. Dark, sustained, synth-swell feel. |
| `STRINGS` | Mid-boost parametric EQ + subtle +12 blend + large hall 80% wet. Warm orchestral-ish. |

## Pitch detection

An input tap runs YIN (de Cheveigné & Kawahara, 2002) on each buffer
and publishes the detected note to the `DETECTED` readout. An RMS
silence gate suppresses noise, and the last detected note is held for
~400 ms to avoid flicker between breaths or consonants. It's there for
visibility — nothing in the audio path depends on it.

## Drums

Patterns are pure functions of `(state, tick)`:

| LVL | Pattern |
|-----|---------|
| 1 | Kick 1&3, snare 2&4, hi-hat quarters |
| 2 | Kick 1&3, snare 2&4, hi-hat 8ths |
| 3 | Kick 1, 3, and-of-3; snare 2&4 + e-of-4 ghost; hi-hat 16ths |

## Files

- `App.swift` — entry point, coordinator wiring, device bootstrap
- `AppState.swift` — `ObservableObject` with tempo, mix, detection, routing state
- `AudioEngine.swift` — single `AVAudioEngine` with drum players, per-instrument mixers, and the live input → EQ → reverb → pad-mixer chain
- `AudioDevices.swift` — CoreAudio helpers for default input/output device names
- `Clock.swift` — 16th-note timer, tap tempo, transport
- `Generators.swift` — pure drum pattern function
- `KeyboardHandler.swift` — NSEvent local monitor
- `PitchDetector.swift` — stateless YIN processor driven by the engine's input tap
- `ContentView.swift` — SwiftUI HUD
