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
  "kit": "Vinyl",
  "pad": "soft",
  "bass": "soft",
  "parts": {
    "verse": {
      "pattern": 5,
      "chords": ["Bm", "G", "D", "D"],
      "repeats": 2,
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
| `pad`, `bass` | song | Pad/bass *sound* folder name. Required only if any part uses them. |
| `parts` | song | Dictionary of part definitions, referenced by name. |
| `structure` | song | Array of part names, in play order. The same name can appear multiple times. |
| `pattern` | part | Drum pattern name from `patterns.json` (e.g. `"Rock basic"`, `"Four on the floor"`). |
| `chords` | part | The chord progression of the part — one symbol per bar of the progression. |
| `repeats` | part | How many times the chord progression cycles. Optional, default 1. Total bars = `chords.length × repeats`. |
| `pad`, `bass` | part | Complexity 0–3 (0 = silent). Default 0. |
| `lyrics` | part | Optional multi-line string. |
| `visual` | part | Optional filename of an animated GIF under `~/BackTrack/Visuals/gifs/`. Displayed as a CSS-cover background behind the synth visuals. |

**Thinking in progressions**: `chords` defines one cycle of harmonic
movement; `repeats` says how many cycles that part plays through. A
verse that says "Bm G D D, repeated twice" is `chords: ["Bm","G","D","D"]`
and `repeats: 2` — eight bars total. For a part with an asymmetric
progression that shouldn't loop, set `repeats: 1` and list every bar's
chord in `chords`.

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
| 3 | Arpeggio — cycle the chord's own tones on 8th notes (triad = root / 3rd / 5th; explicit 7th chords add the 7th). Never synthesizes extensions, so it stays diatonic. |

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
| `↑` / `↓` | Next / previous part. Wraps around (up from last part → first). While stopped: immediate; Space starts from the selected part. While playing: queued to next bar; repeated presses accumulate. |
| `T` | Tap tempo (live override) |
| `R` | Reload songs, samples, and patterns from disk (samples only need this — song JSONs and `patterns.json` auto-reload within ~1 s of being saved) |
| `L` | Toggle loop-current-part — disables auto-advance so the part repeats indefinitely. Great for auditioning drum patterns. |
| `[` / `]` | Previous / next drum pattern for the current part. Change is live (next bar) but in-memory only until saved. |
| `⌘ S` | Save in-memory pattern edits back to the song's JSON. |
| `V` | Show / hide the visuals window. |
| `F` | Toggle the visuals window into macOS native full-screen (title bar auto-hides, window covers the display). Opens the window first if it was closed. |
| `K` / `S` / `H` | Cycle kick / snare / hi-hat volume |
| `P` / `B` | Cycle pad / bass volume |

Volume cycle: `100 → 75 → 50 → 0 → 100`.

## HUD

Two-column layout, 1000×560. The left column is stable (performance
info that can't shift); the right column holds the variable-length
song header + lyrics so long verses don't push the left-column
readouts around.

**Left column:**

- **Structure**: all parts in play order, current one wrapped in `▸ ◂`. Wraps to multiple lines for long structures.
- **Bar counter**: `bar N / M` plus a one-cell-per-bar progress bar (`█░░░`) so remaining bars in instrumental sections are glanceable.
- **Chord line**: current chord large (40pt), next bar's chord dim to the right, and four 1 / 2 / 3 / 4 beat dots on the right that track the current beat so you can come in on the one.
- **Mix**: three rows, one per role. `DRUMS` shows the current pattern + kit; `PAD` / `BASS` show the active sound. Each row has its own activity light (drums light fires on any kick / snare / hh hit). Volumes cycle via K / S / H / P / B — muted rows get a dim `(muted)` badge. A `*` after the pattern name means the current part has unsaved in-memory pattern edits.
- **Loop badge**: when loop-current-part is on (`L` toggle), a bright `LOOP` appears in the structure header.
- **Transport**: `● PLAYING` / `○ STOPPED`.
- **Issues**: `MISSING SAMPLES` and `SONG ISSUES` blocks appear when files are missing or a song file fails to parse.
- **Keybindings**.

**Right column:**

- **Song header**: name, key, tempo.
- **Lyrics**: full text of the active part, larger and line-spaced for readability at arm's length.
- **OUT**: system default output device with a signal-present dot.

## Drum patterns (`patterns.json`)

`~/BackTrack/Samples/patterns.json` defines every drum pattern by name.
Each pattern is an object with `name`, `kick`, `snare`, `hh` — grids
are 16-character strings where `X` is a full hit, `x` is a ghost, `.`
is a rest, and spaces are ignored. Songs reference patterns by the
`name` string. Pattern names are unique; redefining a name overrides
the built-in default.

The shipped library ships 22 patterns, indie-rock-leaning:

| Name | Feel |
|------|------|
| Minimal pulse | Kick 1 only, hi-hat quarters |
| 4/4 | Classic kick 1&3 / snare 2&4 / quarter hats |
| 4/4 Drive | Four-on-floor kick, snare 2&4, ghosted 8th hats |
| Rock minimal | Kick 1, snare 3, 8th hats |
| Rock basic | Kick 1 + 1+, snare 3, 8th hats |
| Rock 16th | Kick 1, 2+, 4+, snare 3, 8th hats |
| Boom-bap min | Kick 1, snare 3, hats on 2 & 4 |
| Boom-bap | Kick 1&3, snare 3 + ghost 4e, 8th hats |
| Boom-bap max | Same backbone, more driving feel |
| Kicks | Kick 1&3, quarter hats, no snare |
| Backbeat 8ths | Kick 1&3, snare 2&4, 8th hats |
| Backbeat ghosts | Backbeat + ghost snare on 4e |
| Four on the floor | Kick every quarter, snare 2&4, 8th hats |
| Motorik | Four-on-floor, ghost snares, 16th hats (kraut rock) |
| Driving 8ths | Kick 1, 2+, 3, 4+, snare 2&4, 8th hats |
| Half-time | Kick 1, snare 3, quarter hats — slow indie |
| Stop-time | Kick 1&3, snare 2&4, no hats — dramatic drops |
| Offbeat hats | Kick 1&3, snare 2&4, hats only on offbeats |
| Chorus lift | Kick 1, 2+, 3, 4, snare 2&4, 16th hats — big chorus |
| Snare build | Kick 1, snare roll on beat 4 — fill into chorus |
| Verse hush | Kick 1&3, no snare, ghost hats 2&4 — whispered verse |
| Outro wind-down | Kick 1, snare 4, quarter hats — tapered exit |

Edit the file to customize any of them or add your own. Auto-reloads
on save (within ~1 s).

### Auditioning patterns live

Finding the right pattern by editing the JSON and reloading gets old
fast. In-app keyboard audition:

1. Play the song, navigate to the part in question with `↑ ↓`.
2. Press `L` to loop the current part indefinitely.
3. `[` / `]` cycle through every pattern in `patterns.json` — the
   change is live on the next bar. A `*` appears next to the pattern
   name to remind you the edit is in-memory only.
4. When you find one you like, `⌘ S` saves it back to the song's
   JSON (pretty-printed, sorted keys). `L` again to exit loop mode.
5. If you don't save, the pattern reverts to whatever's on disk the
   next time you reload.

## Visuals window

Second window that renders per-part background clips + console-style
geometric visuals reactive to the same trigger timestamps the HUD
uses. Drag it to a secondary monitor or a projector; press `F` to
toggle macOS native full-screen.

Background layer — animated GIFs placed at
`~/BackTrack/Visuals/gifs/` and referenced per part via the `visual`
field. Scaled CSS-cover style: fills both axes, preserves aspect
ratio, crops whatever overflows.

Synth layer (on top of the background, back to front):

| Voice | Shape |
|-------|-------|
| *idle* | Thin always-on border for projector / screen alignment |
| Pad | 12 spinning spokes in a donut band (22–48% of min dim); brightness tracks pad activity; only visible while the pad is firing |
| Kick | Thick outer border flash |
| Bass | Ring at ~40% radius |
| HH | Ring at ~13% radius around the snare dot |
| Snare | Filled dot in the center |

Everything is sized proportionally to `min(width, height)` so it holds
up on any aspect ratio. Pale-green monochrome to match the HUD.
Toggle visibility with `V`; full-screen with `F`.

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
- `VisualsView.swift` — Canvas-based console visuals window
- `GifView.swift` — animated-GIF background layer with CSS-cover scaling
