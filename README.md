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

Each drum kit is a subdirectory under `~/BackTrack/Samples/drums/`
containing `kick`, `snare`, and `hh` samples:

```
~/BackTrack/Samples/
└── drums/
    ├── acoustic/
    │   ├── kick.{wav|aif|aiff|mp3}
    │   ├── snare.{wav|aif|aiff|mp3}
    │   └── hh.{wav|aif|aiff|mp3}
    ├── 808/
    │   ├── kick.wav
    │   ├── snare.wav
    │   └── hh.wav
    └── vintage/
        └── ...
```

Subdirectory names are the kit names. They're loaded alphabetically at
startup. Press `D` to cycle through kits in real time; the HUD shows
the current kit name and its position in the list.

If you have flat samples directly at `~/BackTrack/Samples/drums/` from
an older setup, they're still picked up as a single kit called
`default`.

Missing samples appear in the HUD under `MISSING SAMPLES`. Press `R`
to reload (rescans for new kits too). There are no pad samples — the
pad is generated live from your mic input.

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
| `D`     | cycle drum kit                           |
| `K`     | kick volume (cycles 100 → 75 → 50 → 0 → 100) |
| `S`     | snare volume                             |
| `H`     | hi-hat volume                            |
| `P`     | cycle pad mode (OFF → SIMPLE → SHIMMER → SYNTH → STRINGS → OFF) |

Queued (commit on beat 1 of the next bar):

| Key     | Action                           |
|---------|----------------------------------|
| `1`–`9`, `0` | drum pattern (10 variants, see below) |

## HUD

Three groups, top to bottom.

**Upper block — global state**

| Readout | Meaning |
|---------|---------|
| `BPM` | Current tempo |
| `PATTERN` | Active drum pattern (1–10) |
| `KIT` | Active drum kit name, with `(i/n)` counter when multiple kits exist |
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
| `SIMPLE` | High-pass + quarter-note delay (BPM-synced, 60% feedback, darkened echoes) + large hall 75% wet |
| `SHIMMER` | Dry + strong +12 octave layer + large hall 80% wet. Arrives sooner than the old cathedral-based version. |
| `SYNTH` | Low-pass at 2.5 kHz + −12 sub-octave + mild distortion + medium hall 70% wet. Dark, gritty, tighter sustain. |
| `STRINGS` | Parametric mid-boost at 800 Hz + subtle +12 blend + medium hall 65% wet. Warm, responsive, orchestral-ish. |

The BPM-synced quarter-note delay in SIMPLE updates whenever tempo
changes (arrow keys, tap tempo).

## Pitch detection

An input tap runs YIN (de Cheveigné & Kawahara, 2002) on each buffer
and publishes the detected note to the `DETECTED` readout. An RMS
silence gate suppresses noise, and the last detected note is held for
~400 ms to avoid flicker between breaths or consonants. It's there for
visibility — nothing in the audio path depends on it.

## Drums

Ten drum patterns, one per number key (`1`–`9`, `0` = 10). Grouped in
threes by "feel", each group ramping simple → busier; pattern 10 is
a sparse outlier that restarts the simplicity cycle.

The default patterns are listed in the HUD by name when you switch
to them. They're fully editable — see the next section.

### Editing patterns

Drop a file at `~/BackTrack/Samples/patterns.json` to override any
or all of the built-in patterns. Each pattern is an object with a
`name` plus three 16-character grids (`kick`, `snare`, `hh`):

```json
[
  {
    "name": "Half-time rock",
    "kick":  "X . . . . . . . . . . . . . . .",
    "snare": ". . . . . . . . . . . . X . . .",
    "hh":    "X . X . X . X . X . X . X . X ."
  },
  {
    "name": "Four on the floor",
    "kick":  "X . . . X . . . X . . . X . . .",
    "snare": ". . . . X . . . . . . . X . . .",
    "hh":    ". . X . . . X . . . X . . . X ."
  }
]
```

Grid characters:

| Char | Meaning |
|------|---------|
| `X` or `O` | full hit (velocity 1.0) |
| `x` or `o` | ghost hit (velocity 0.35) |
| `.` | rest |
| spaces | ignored (use them for readability) |

Rules:

- The bar is 16 sixteenth-note ticks. Position 0 is beat 1, position 4
  is beat 2, position 8 is beat 3, position 12 is beat 4.
- Entries in the JSON array map to keys `1`, `2`, `3`, … `9`, `0` in
  that order. Slots you omit keep their built-in default.
- Press `R` in the app to hot-reload `patterns.json` without
  restarting. If the file is missing or malformed, all ten built-in
  defaults are used; parse errors are logged to stderr.

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
