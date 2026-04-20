# BackTrack

A minimal, song-based backing-track player for live solo practice and
performance. Songs are JSON files that define parts, chord progressions,
drum patterns, and lyrics; BackTrack plays them back with sample-based
drums, pitch-shifted pad chords, and bass. Keyboard-driven. Native macOS.

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode or Command Line Tools)
- Headphones / routed monitor (no live-input processing; output is the
  backing track)

## Samples

Each instrument's sounds live in a named subdirectory under
`~/BackTrack/Samples/`:

```
~/BackTrack/Samples/
├── drums/
│   ├── default/{kick,snare,hh}.{wav|aif|aiff|mp3}
│   ├── 808/{kick,snare,hh}.wav
│   └── vintage/...
├── pads/
│   ├── strings/pad_C.wav       (pitch class in the filename)
│   ├── soft/pad_A.aif
│   └── hard/pad_E.wav
├── bass/
│   ├── 80s/bass_E.wav
│   ├── soft/bass_C.aif
│   └── hard/bass_A.wav
└── patterns.json               (drum pattern definitions, optional)
```

- **Drum kit** = folder under `drums/` with `kick`, `snare`, `hh`.
- **Pad / bass sound** = folder under `pads/` or `bass/` containing one
  pitched sample named `pad_<NOTE>.<ext>` / `bass_<NOTE>.<ext>`. The note
  letter (with optional sharp/flat) is parsed from the filename; any
  octave digit is tolerated but ignored — pitch-shifting is relative to
  the pitch class you recorded at.
- Files load into a canonical 44.1kHz/stereo format at load time, so
  switching sounds/kits is a zero-glitch buffer swap.

Songs reference kit/sound folder names by string.

## Songs

Each song is a JSON file under `~/BackTrack/Songs/`. At launch, BackTrack
scans the directory; any malformed songs surface in the HUD's
`SONG ISSUES` block with a pointer to the line of trouble.

### Schema

```json
{
  "name": "Song Title",
  "key": "D major",
  "bpm": 90,
  "kit": "default",
  "pad": "strings",
  "bass": "soft",
  "parts": {
    "verse": {
      "pattern": 5,
      "bars": 4,
      "chords": ["Bm", "G", "D", "D"],
      "pad": 2,
      "bass": 0,
      "lyrics": "line one\nline two"
    }
  },
  "structure": ["intro", "verse", "chorus", "verse", "chorus", "outro"]
}
```

| Field | Where | Meaning |
|-------|-------|---------|
| `name`, `key`, `bpm` | song | Display + tempo. `key` is informational. |
| `kit` | song | Drum kit folder name under `drums/`. |
| `pad`, `bass` | song | Pad/bass *sound* folder name (strings). Required only if any part uses them. |
| `parts` | song | Dictionary of part definitions, referenced by name. |
| `structure` | song | Array of part names, in play order. The same name can appear multiple times. |
| `pattern` | part | Drum pattern 1–10 (index into `patterns.json`). |
| `bars` | part | Bar count. `chords.length` must equal this. |
| `chords` | part | Array of chord symbols, one per bar. |
| `pad`, `bass` | part | Complexity 0–3 (0 = silent). Default 0. |
| `lyrics` | part | Optional multi-line string. |

### Chord notation

Keep it simple: `D`, `Dm`, `D7`, `Dmaj7`, `Dm7`. Accepted variants:
`Dmin` = `Dm`, `Dmaj` = `D`, case-insensitive. Flats with `b`
(`Bb` = `A#`). Anything else (sus, dim, aug, slash, 9ths, 11ths, etc.)
is a parse error.

### Pad complexity

| Level | Behavior |
|-------|----------|
| 0 | Silent |
| 1 | Drone — root + 5th, one trigger per chord change, sustained |
| 2 | Stabs — full triad retriggered on quarter notes |
| 3 | Arpeggio — extended chord (root / 3rd / 5th / 7th / 9th) on 8th notes |

On chord changes within a part (and on part transitions), the previous
chord's pad and bass voices are faded out so long sustained samples
don't bleed across the transition. Same-chord bars keep the drone
ringing.

### Bass complexity

| Level | Behavior |
|-------|----------|
| 0 | Silent |
| 1 | Whole — root on beat 1 of each bar |
| 2 | Half — root on beats 1 and 3 |
| 3 | Pump — root on every quarter note |

## Run

```
swift run
```

Or:

```
swift build -c release
./.build/release/BackTrack
```

## Keybindings

| Key | Action |
|-----|--------|
| `Space` | Start / stop |
| `←` / `→` | Previous / next song (stops playback) |
| `↑` / `↓` | Next / previous part (queued to next bar) |
| `T` | Tap tempo (live override) |
| `R` | Reload songs, samples, and patterns from disk |
| `K` / `S` / `H` | Cycle kick / snare / hi-hat volume |
| `P` / `B` | Cycle pad / bass volume |

Volume cycle: `100 → 75 → 50 → 0 → 100`.

## HUD

- **Header**: song name, key, tempo.
- **Structure**: all parts in play order, current one wrapped in `▸ ◂`, bar counter.
- **Chord line**: current chord large, next bar's chord dim to the right.
- **Lyrics**: full text of the active part.
- **Mix**: compact chips for KICK / SNARE / HH / PAD / BASS with activity dot and level meter. PAD and BASS show the active sound name as a subtitle.
- **Transport**: `● PLAYING` / `○ STOPPED`.
- **Upper right**: system output device with a signal-present dot.
- **Issues**: `MISSING SAMPLES` and `SONG ISSUES` blocks appear when files are missing or a song file fails to parse.

## Drum patterns (`patterns.json`)

Optional file at `~/BackTrack/Samples/patterns.json` overrides the ten
built-in patterns. See the existing file for format; grids are strings
of 16 characters where `X` is a full hit, `x` is a ghost, `.` is a rest,
and spaces are ignored.

## Files

- `App.swift` — entry point, coordinator wiring
- `AppState.swift` — observable state (songs, transport, mix)
- `AudioEngine.swift` — AVAudioEngine graph, sample loading, pitched voice pools
- `AudioDevices.swift` — CoreAudio helpers for default output device name
- `ChordParser.swift` — chord symbol → root pitch class + quality + 7th
- `Clock.swift` — 16th-note timer, song playback engine, tap tempo
- `ContentView.swift` — SwiftUI HUD
- `Generators.swift` — drum pattern loader, pad + bass generators
- `KeyboardHandler.swift` — NSEvent local monitor
- `Song.swift` — Song / Part structs + raw JSON schema
- `SongLoader.swift` — directory scan + validation
