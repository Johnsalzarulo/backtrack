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
      "pattern": "Rock basic",
      "chords": ["Bm", "G", "D", "D"],
      "repeats": 2,
      "pad": 2,
      "bass": 1,
      "lyrics": "line one\nline two",
      "visuals": "chaplinstill.gif"
    },
    "chorus": {
      "pattern": "Chorus lift",
      "chords": ["Bm", "G", "D", "D"],
      "repeats": 2,
      "pad": 3,
      "bass": 2,
      "lyrics": "chorus line",
      "visuals": ["hands.gif", "bigbird.gif", "napoleon.gif"],
      "visualMode": "beat"
    }
  },
  "structure": ["intro", "verse", "chorus", "verse", "chorus", "outro"],
  "theme": "dark",
  "visualizer": "constellation"
}
```

| Field | Where | Meaning |
|-------|-------|---------|
| `name`, `key`, `bpm` | song | Display + tempo. `key` is informational. |
| `kit` | song | Drum kit folder name under `drums/`. |
| `pad`, `bass` | song | Pad/bass *sound* folder name. Required only if any part uses them. |
| `parts` | song | Dictionary of part definitions, referenced by name. |
| `structure` | song | Array of part names, in play order. The same name can appear multiple times. |
| `theme` | song | `"dark"` (default — black paper, white ink) or `"light"` (inverted). Only affects the synth layer of the visuals window; parts with a `visuals` file aren't themed. |
| `visualizer` | song | Synth-layer motif. One of `"constellation"` (default), `"orbit"`, `"ink"`, `"squares"`, `"dots"`, `"lines"`, `"ripple"`, `"lyrics-block"`, `"lyrics-line"`. See the Visuals window section below. |
| `countIn` | song | Optional integer. When > 0, pressing Space plays N bars of metronome clicks (4 hi-hat hits per bar at the song's BPM, beat 1 accented) before the song actually starts. The HUD shows `● COUNT-IN n/N` and the visuals window shows the current beat-in-bar number large. Default 0 = no count-in. |
| `pattern` | part | Drum pattern name from `patterns.json` (e.g. `"Rock basic"`, `"Four on the floor"`). |
| `chords` | part | The chord progression of the part — one symbol per bar of the progression. |
| `repeats` | part | How many times the chord progression cycles. Optional, default 1. Total bars = `chords.length × repeats`. |
| `pad`, `bass` | part | Complexity 0–3 (0 = silent). Default 0. |
| `lyrics` | part | Optional multi-line string. |
| `visuals` | part | Optional filename (string) **or** array of filenames under `~/BackTrack/Visuals/`. Still images (PNG/JPEG/…), animated GIFs, and videos (mp4, mov, m4v, mpg, mpeg, webm, avi) are all supported. Displayed CSS-cover and takes over the visuals window (the synth layer is suppressed while a visual is on screen). |
| `visualMode` | part | Only meaningful when `visuals` is an array. `"bar"` (default) advances to the next visual at each bar boundary; `"beat"` advances on every quarter-note beat. Arrays cycle — shorter than the part length wraps; longer gets truncated at whatever index you land on when the part ends. |
| `visualizer` | part | Optional per-part override of the song-level `visualizer`. Same vocabulary. Useful for e.g. a chorus in `"lyrics-block"` while the rest of the song stays geometric. A part with a `visuals` GIF still shows the GIF — the per-part visualizer only renders when that part has no `visuals`. |

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

## Countdowns

Countdowns are pre-show / interval timers — the second deck you can
navigate alongside songs. They live in their own directory and render
as a full-screen TV-style display: a label, a giant counting timer, a
progress bar, and a rotating block of one-liner messages. (Eventually
countdowns and songs will share one setlist; today they're toggled
with `D`.)

```
~/BackTrack/Countdowns/preshow.json
```

### Schema

```json
{
  "name": "Pre-show",
  "duration": 600,
  "label": "Show begins in",
  "messageInterval": 6,
  "messages": [
    "You still have time to go to the bathroom",
    "Stop watering dead plants",
    "Brought to you by Lexapro"
  ]
}
```

| Field | Meaning |
|-------|---------|
| `name` | Display name in the HUD's countdowns list. |
| `duration` | Required. Total length of the countdown, in seconds. |
| `label` | Optional. Header text above the timer. Default `"Show begins in"`. |
| `messageInterval` | Optional. Seconds per rotating message. Default `6`. |
| `messages` | Optional. List of one-liners that cycle below the timer. Index advances by 1 every `messageInterval` seconds. Empty list = no rotating message. |

### Transport

Press `D` to switch the active deck to countdowns. Then:

- `←` / `→` — previous / next countdown (resets the timer)
- `Space` — start → pause → resume → pause → ... (timer keeps its place)
- `D` again — back to the song deck (stops the countdown)

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
| `I` | Invert the synth-layer theme (dark ↔ light). Live in-memory override on top of the song's `theme` JSON — not persisted. |
| `M` | Cycle the synth-layer motif: constellation → orbit → ink → squares → dots → lines → ripple → lyrics-block → lyrics-line → (song default). Same in-memory override behavior as `I`. |
| `D` | Toggle the active deck between songs and countdowns. Stops anything currently playing on the deck you're leaving. |
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

- **Song header**: name, key, tempo. Tempo dims briefly on each tap-tempo hit as visual feedback.
- **Lyrics**: full text of the active part, larger and line-spaced for readability at arm's length.
- **Next part peek**: a `NEXT — PARTNAME` line under the lyrics shows the first line of the upcoming part (or the queued part if `↑ ↓` is pending), so the first lyric of a chorus isn't a surprise when you're starting from an instrumental intro.
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

Second window with two modes per part: either a **visual** (image /
GIF / video) takes over the whole window, or the **synth layer**
(console-style geometric visualizers reactive to drum / pad / bass
triggers) runs. Drag it to a secondary monitor or a projector; press
`F` to toggle macOS native full-screen.

### Visual layer

Drop files into a single flat folder at `~/BackTrack/Visuals/`. No
subdirectories — parts reference files by filename only.

| Type | Extensions | Backend |
|------|------------|---------|
| Still image | `.png`, `.jpg` / `.jpeg`, `.tiff`, `.heic`, `.bmp` | `NSImageView` |
| Animated GIF | `.gif` | `NSImageView` (auto-animates) |
| Video | `.mp4`, `.mov`, `.m4v`, `.mpg` / `.mpeg`, `.m2v`, `.webm`, `.avi` | `AVPlayerLayer` (muted, looped seamlessly) |

All media is scaled CSS-cover style: fills both axes, preserves aspect
ratio, crops whatever overflows. Videos play muted — BackTrack is the
only audio source.

Each part can specify either a single visual or an array that cycles
during playback, controlled by `visualMode`:

- `"bar"` (default) — advance to the next visual at each bar.
- `"beat"` — advance on every quarter-note beat (4× faster).

Arrays wrap around if the part is longer than the list. Common pattern:
keep verses / intros low-key with a single image, and give choruses an
array (sometimes in `"beat"` mode) to build visual energy.

### Synth layer

Only rendered when the current part has **no** visual — layering the
two was too busy on screen. The vocabulary is black-and-white linocut:
chunky shapes with slightly wobbly edges, 100% saturated ink on solid
paper, no greys, no fades.

**Binary on/off.** Every voice is either fully drawn or completely
absent. A hit pops the shape on for a short hold window (60 ms for HH
up to 450 ms for pad), then it's gone until the next trigger.
Responsiveness beats transition polish — shapes appearing / vanishing
in time with the audio is what sells the "this is reacting to the
music" feeling.

**Organic feel without flicker.** Comes from two permanent properties
of the shapes, not from animation:
- every vertex has a stable hash-based offset, smoothed across its
  4 nearest neighbors so edges read as carved rather than as teeth
- every vertex is also perturbed by a ~0.6 Hz sine wobble keyed to
  angular position (one or two gentle lobes around the perimeter,
  never an N-pointed star), so longer-held shapes breathe subtly

**Geometric motifs.** Each song picks a visualizer style via its
`visualizer` JSON field. The seven geometric motifs share the same
shape vocabulary — they differ in *what each voice becomes* and
*where it goes*.

| Motif | Kick | Snare | Bass | HH | Pad | Extras |
|-------|------|-------|------|-----|-----|--------|
| `constellation` *(default)* | Center star | Upper-right star | Lower-left star | Lower-right star | 4/6/8 stars on outer orbit | — |
| `orbit` | Small body orbiting at ≈14% r, 6 s | Body at ≈22% r, 9 s | Body at ≈40% r, 18 s | Body at ≈30% r, 12 s | 2/3/4 bodies at ≈48% r, 24 s | Bar-progress arc on outer ring at ≈56% r |
| `ink` | Uniform radial expansion | Sharp narrow spikes at ~5 seeded vertices (re-picked per beat) | Horizontal polarization (bi-lobed stretch) | High-freq ripples around the perimeter (shimmer) | Slow 2-lobe wobble drifting over time | Always-on resting wobble + 6 splatter drops (re-seeded per bar) |
| `squares` | Big filled square, center | Smaller filled square | Hollow square ≈36% r | Small hollow square | 4/6/8 tiles on an orbit | — |
| `dots` | Big filled dot, center | Smaller dot | Ring of 12 dots | Tight ring of 8 tiny dots | 4/6/8 scattered dots | — |
| `lines` | Thick wide horizontal bar, center | Thin bar below kick | Long bar above center | Short tick below snare | 4/6/8 dashes stacked above | — |
| `ripple` | Thick ring ≈42% r | Ring ≈26% r | Biggest ring ≈54% r | Tiny inner ring ≈11% r | 4/6/8 thin rings between | — |

Pad count (4 / 6 / 8) tracks the part's `pad` level (1 / 2 / 3).
`orbit` adds a bar-progress arc on its outer ring — non-voice
dynamic info the other motifs don't surface.

**`ink` breaks the binary on/off rule.** Every other motif either
draws a voice's shape at full size or not at all. Ink instead lets
each voice apply a *continuously decaying force* to the central
mass's perimeter over the hold window, so the ferrofluid flows
smoothly between shapes rather than teleporting. Ink color stays
100% saturated throughout — only the shape deforms — so the no-greys
rule is preserved.

**Lyric motifs.** Three additional styles render the current part's
`lyrics` field typographically — useful as a teleprompter or a visual
rhythm reinforcement for songs where the words carry the feel. Parts
with no lyrics (intros / instrumentals) show as blank paper.

| Motif | Behavior |
|-------|----------|
| `lyrics-block` | All lyrics of the part as a single justified paragraph, newlines → spaces. Font size binary-searches to fill the frame edge to edge. Doesn't animate during the part — one big paragraph, stable while that part plays. |
| `lyrics-line` | Current line, one at a time. Lines change at even time intervals within the part: `lineIndex = floor(playbackFraction × lineCount)`. Line changes are quantized to the beat. |

Lyric timing uses a beat-quantized playback fraction
(`(currentBar × 4 + currentBeat) / (part.bars × 4)`) — approximate but
feels in sync at normal tempos.

**Theme.** Set `"theme": "dark"` (default: black paper, white ink) or
`"light"` (white paper, black ink) on the song.

**Live overrides.** `I` inverts theme; `M` cycles through the eight
motifs (six geometric, two lyric) plus a ninth "song default" stop.
Both are in-memory only — not written back to JSON. Useful for
auditioning. The song's JSON values remain the source of truth for
"what this song looks like by default"; the overrides just replace
them for the current session.

When a visualizer override is active, the synth layer takes priority
over any part-level visual (GIF / image / video) — so pressing `M`
on a part with a `visuals` file actually cycles something you can
see instead of silently updating the hidden synth layer underneath.
Cycle past `lyrics-line` and you land on the "song default" stop,
which clears the visualizer override and restores the part's
`visuals` (or the song's JSON visualizer if the part has none).
`I` alone never hides a GIF — theme doesn't affect GIF display, so
the theme override just waits in memory until you navigate to a
synth view.

**Overscan safety.** Every motif except the part-level visual (GIF /
image / video) is inset by 7% of `min(width, height)` on each edge,
so CRT/projector overscan won't clip shapes or text. Part-level
visuals stay edge-to-edge since they're expected to fill the frame
and cropping would just show paper-colored bars.

**Idle state.** When transport is stopped and the current part
wouldn't be showing a GIF/image/video, the window fills with TV
static (theme-aware — white flecks on black in dark mode, black on
white in light). This is the "no signal" resting state at app
launch, between songs, and any time you hit Space to pause.
Regenerates at ~15 Hz to feel analog rather than digital.

Everything else is sized proportionally to `min(width, height)` so
it holds up on any aspect ratio. Toggle the whole window with `V`;
full-screen with `F`.

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
- `VisualsView.swift` — Canvas-based synth-layer visuals window, switches to the visual backend when a part has one; dispatches between the geometric and lyric motifs
- `LyricsVisualizers.swift` — NSViewRepresentable auto-fitting justified-text view, plus the centered single-line/word view
- `VisualView.swift` — NSViewRepresentable for images / GIFs (via NSImageView) and video (via AVPlayer), all with CSS-cover scaling
- `IdleStaticView.swift` — TV static / "no signal" idle state, shown when transport is stopped with no part-level visual
