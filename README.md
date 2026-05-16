# BackTrack

A minimal, song-based backing-track player for live solo practice and
performance. Songs are JSON files that define parts, chord progressions,
drum patterns, and lyrics; BackTrack plays them back with sample-based
drums, pitch-shifted pad chords, and bass. Keyboard-driven. Native macOS.

Two of the keys (`1` / `2`) are wired to physical red and green buttons
in front of the audience, giving them direct, momentary control over the
visuals window — see [Audience interaction](#audience-interaction).

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
| `visualizer` | song | Synth-layer motif. One of `"constellation"` (default), `"orbit"`, `"ink"`, `"squares"`, `"dots"`, `"lines"`, `"ripple"`, `"oscilloscope"`, `"lyrics-block"`, `"lyrics-line"`. See the Visuals window section below. |
| `countIn` | song | Optional integer. When > 0, pressing Space plays N bars of metronome clicks (4 hi-hat hits per bar at the song's BPM, beat 1 accented) before the song actually starts. The HUD shows `● COUNT-IN n/N` and the visuals window shows the current beat-in-bar number large. Default 0 = no count-in. |
| `visualEffect` | part | Optional. Post-processing layer wrapping the entire visuals window for this part. One of `"none"` (default), `"glitch"` (beat-synced digital-corruption jitter + slice flashes; every 4th bar's downbeat fires a major tear with longer decay and ~3× slice count), `"tracking"` (continuous VCR distortion band + slight VHS desaturation; every ~6 s the picture rolls vertically with a sync seam at the wrap point), `"chroma"` (RGB channel separation; per-beat random angle, downbeat boost, part-start blowout — Spider-Verse / vintage 3D feel). Different parts can have different effects. The audience-facing green button (`1`) can temporarily override this with a 10-second auto-reverting effect — see [Audience interaction](#audience-interaction). |
| `videoClip` | part | Optional filename in `~/BackTrack/VideoClips/` (mp4, mov, m4v, mpg, mpeg, m2v, webm, avi). When set, plays once with audio when the part starts, taking over the visuals window. The backing track keeps playing alongside. When the clip ends mid-part, the visuals window falls back to the part's normal `visuals` / `visualizer`. While a `videoClip` is playing, both audience-facing buttons (`1` and `2`) are suppressed — the clip owns the screen. |
| `videoClipVolume` | part | Optional integer 0–100, default 100. Audio gain for `videoClip`. Ignored when `videoClip` is unset. |
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

Countdowns are pre-show / interval timers that share the lineup with
songs and interstitials (see [Setlists](#setlists)). They render
full-screen as a label up top, a timer visualization in the middle
(digital, pie, or hourglass — see `style` below), a rotating block of
one-liner messages beneath, and a small static `press 🔴 or 🟢` line
at the very bottom that trains the audience to use the red/green
buttons in front of them.

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
| `style` | Optional. How the timer renders. One of `"digital"` (default — giant `M:SS:cc` digits + thin progress bar), `"pie"` (clock-face wedge that shrinks clockwise from 12 with smaller `M:SS` digits below), `"hourglass"` (sand draining from top to bottom triangle, `M:SS` below). Label and rotating message look the same across all three. The audience-facing green button (`1`) cycles this at runtime (digital → pie → hourglass) without modifying the JSON; the override is wiped when the lineup cursor moves. |
| `visualEffect` | Optional. Post-processing layer wrapping the entire countdown. One of `"none"` (default), `"glitch"`, `"tracking"`, `"chroma"`. Same options exist as part-level fields on songs. Beat-synced behaviors idle gracefully when nothing's playing. Audience buttons don't touch this on countdowns — `1` cycles `style` and `2` advances the rotating message. |

### Audience interaction

Every countdown shows a small `press 🔴 or 🟢` line at the bottom of
the screen, beneath the rotating message, identical across all three
styles. The two audience-facing buttons are wired to:

- `🟢` (key `1`) — cycle the render `style` (digital / pie /
  hourglass). Persists until the lineup cursor moves.
- `🔴` (key `2`) — advance the rotating message immediately. Each tap
  adds 1 to a manual offset that's layered on top of the time-based
  message index, so a press always reveals the next entry without
  waiting for the next interval boundary.

Both overrides are scoped to the active item — moving to the next or
previous lineup item resets the style override and the message
offset. See [Audience interaction](#audience-interaction) below for
the full picture (including what these keys do during songs).

### Transport

Countdowns are part of the unified lineup (see Setlists below). When
the cursor lands on a countdown:

- `Space` — start → pause → resume → pause → ... (timer keeps its place)
- `←` / `→` — leave for the previous / next lineup item (resets the timer)

## Interstitials

The third lineup-item kind, alongside songs and countdowns. An
interstitial shows a single thing on screen while the performer is
between songs — tuning, taking a beat, introducing what's next.

Three flavors: a **text** card, a **still image**, or a **video clip**
with audio. One file per interstitial, under
`~/BackTrack/Interstitials/`.

```
~/BackTrack/Interstitials/welcome.json
```

### Schema

```json
{
  "name": "Welcome",
  "kind": "text",
  "text": "Welcome to the show",
  "notes": "Hi everyone — quick housekeeping then into the first one.",
  "duration": 30,
  "theme": "dark"
}
```

| Field | Meaning |
|-------|---------|
| `name` | Display name; matched by setlist refs. |
| `kind` | One of `"text"` / `"image"` / `"video"`. The required content field below depends on this. |
| `text` | Required for `kind: "text"`. Multi-line via `\n`. Rendered big, centered, theme-tinted (lyrics-block style). |
| `image` | Required for `kind: "image"`. Filename in `~/BackTrack/Visuals/`. CSS-cover full-bleed. |
| `video` | Required for `kind: "video"`. Filename in `~/BackTrack/VideoClips/`. Plays unmuted, full-bleed. |
| `volume` | Video only. Integer 0–100, default 100. |
| `loop` | Video only. Default `false`. When `false`, the video plays once and the lineup auto-advances to the next item when it ends. When `true`, the video keeps replaying until you `←/→` away. |
| `duration` | Optional integer seconds. Auto-advance to the next lineup item after this many seconds. **Text/image only** — for video, the clip's actual length determines auto-advance. |
| `notes` | Optional. Talking points shown in the HUD's right column where song lyrics normally appear — a place for what to say while the visual is on screen. |
| `theme` | `"dark"` (default) / `"light"`. Affects text/background colors for `text` kind. |

### Transport

When the cursor lands on an interstitial, its content shows in the
visuals window immediately — no `Space` needed. The HUD's right
column shows the notes; left column shows an INTERSTITIAL block with
the name + kind.

`←` / `→` navigates away (tears down the video / clears the screen).
`Space` is a no-op for interstitials.

When the auto-advance trigger fires (duration expired for text/image,
non-looping video reached its end), the lineup moves to the next item
on its own.

### Sound during a video interstitial

Only the video's own audio plays — there's no song clock running on a
non-song lineup item, so no drums / pad / bass. Use `volume` (or
edit it in the JSON) to set the level.

## Audience interactives

The fourth lineup-item kind. Where Songs play backing tracks,
Countdowns run timers, and Interstitials show static content,
audience interactives are screens **the audience drives** — using the
red and green hardware buttons in front of them. Designed as a
"mini-app" framework: each kind owns its own screen and its own
per-button semantics over the same two-button vocabulary, so we can
keep adding new audience moments (votes, branches, reactions, etc.)
without inventing a new top-level lineup type each time.

Stored as JSON files under `~/BackTrack/AudienceInteractives/`,
referenced from setlists with `kind: "audience-interactive"`. Same
~1 s hot-reload behavior as the other inventories.

```
~/BackTrack/AudienceInteractives/start_show.json
```

### Schema

```json
{
  "name": "Start Show",
  "kind": "start_button"
}
```

| Field | Meaning |
|-------|---------|
| `name` | Display name in the HUD's audience-interactive list and the string setlists reference. |
| `kind` | Discriminator that picks the screen + behavior. Currently `"start_button"`; future kinds add to this list. The loader is lenient on punctuation (`start_button` / `start-button` / `startbutton` all resolve to the same kind). |

### Kinds

#### `start_button`

A "PRESS 🟢 TO START THE SHOW" gate, intended to live right after
the pre-show countdown. The audience advances the show themselves,
so the run-of-show feels collaborative from the very first moment.

- 🟢 (`1`) — advances the lineup to the next item.
- 🔴 (`2`) — plays a synthesized 8-bit two-tone error beep
  (880 Hz → 440 Hz square wave, 240 ms total) routed through the
  master mixer (so it tracks the music's bed level and never
  dominates the room), and flashes "WRONG BUTTON" in red for
  ~1.5 s before returning to the prompt.
- `Space` — mirrors the green button so the operator can advance
  from the keyboard if the audience freezes up.
- The screen is full-bleed with the same monospace + theme-aware
  styling the countdown uses; the green dot and the red "WRONG
  BUTTON" tint are the only deviations.

#### `transmission`

A multi-step text-message exchange between an unnamed sender and
the audience. The screen shifts to a phosphor-green-on-black CRT
terminal aesthetic (independent of the song theme); messages
arrive one at a time, typing themselves in character-by-character;
the audience picks replies from two button labels at the bottom.
The flow plays out for ~2-5 minutes while the performer pretends
to tune their guitar.

The same `kind: "transmission"` framework hosts any number of
narrative scripts — different files, different stories, same
runtime. Currently shipped:

- `the_breakup.json` — mid-set, between *I Don't Want To Take
  Pills* and *Sleeping Cold*. Audience plays the side that's
  pursuing; the other party has clearly already left. Ends with
  the operator advancing manually after the closing message.
- `moving_on.json` — directly after *Sleeping Cold*. Audience
  plays the side moving on; the other party can't accept it.
  Ends on its own clock — the bit auto-advances back into the
  setlist after the final beat holds.

**Per-exchange flow** (audience-driven exchange):

1. Brief blank pause (~700 ms — "they're typing on the other end").
2. `INCOMING` header (small, dim, top) appears.
3. The body types itself in at ~25 chars/sec. While typing, no
   reply prompts are visible and audience presses are ignored —
   the audience can't skip past a message they haven't seen.
4. Once typing finishes, two reply prompts appear stacked at the
   bottom: 🟢 above, 🔴 below.
5. Audience presses one. Screen briefly shows `YOU SENT: <reply>`
   (~1 s, suppressed for silent / gate / opening choices — see
   below), then back to step 1 with the next exchange.

**Three exchange flavors** the same schema supports:

- **Audience-driven** — has `green` and `red` choices. Audience
  must press to advance. The everyday case.
- **Self-driving (`autoAdvance`)** — declares an `autoAdvance`
  block instead of choices. The exchange types in, holds for
  `holdSeconds` after typing finishes, then auto-transitions to
  its `next`. Used for `OUTGOING` messages (you're sending,
  there's nothing to reply to) and for terminal beats that should
  end the bit on a clock rather than waiting on the operator.
  Mutually exclusive with `green`/`red` — the loader rejects an
  exchange that has both.
- **Terminal-by-operator** — has neither choices nor
  `autoAdvance`. The body sits on screen indefinitely until the
  operator advances with `→` / `Space`. Used by The Breakup's
  closing "mommy issues" beat, where the silence is the point.

**Special exchange shapes**

- **Gate** — `header: "NEW MESSAGE RECEIVED"`, empty `incoming`,
  one button's `next` is `"abort"`. Renders as a large centered
  header with the two choices stacked beneath. Pressing the abort
  side ends the bit before it starts (the audience refused the
  invitation — perfectly valid ending). Both currently shipped
  scripts open with one.
- **`OUTGOING` exchange** — set `header: "OUTGOING"` to flip the
  fiction. The body reads as a message *you* are sending in the
  conversation. Same phosphor monochrome (no separate styling),
  but the header word does the differentiation. Pairs naturally
  with `autoAdvance` since "you" are sending the message; there's
  nothing for the audience to reply to.
- **Silent choice** — wrap a reply label in parens, e.g.
  `"(say nothing)"`. The system detects parens-wrapped labels and
  suppresses the `YOU SENT: …` echo for them — semantically the
  audience didn't send anything, just declined to respond. Author
  doesn't need a schema flag; the parens are the signal.
- **GAME OVER beat** — set `header: "GAME OVER"` (or whatever
  closing label you want), wrap the dramatic copy in the `incoming`
  body, and add `arrivalSound: "death"` + `autoAdvance` with a
  longish hold + `next: "abort"`. The phosphor screen plays the
  pac-man-style descending arpeggio when the exchange begins, the
  body types in, the screen holds for the lineup-advance timer,
  then the bit ends. Used as The Breakup's closer — "YOUR
  RELATIONSHIP IS OVER / You cannot replay."

**Sound effects** — short synthesized 8-bit SFX, all routed
through the master mixer (so they track the music's bed level
instead of overpowering it):

| Sound | When it fires | Description |
|---|---|---|
| `doot` (arrival) | Default for gate exchanges (empty body) | Two ascending square-wave tones (A5 → E6, ~190 ms) — announces the opening message |
| `doot` (press) | Every audience button press during a transmission, including silent choices and DELETE | Same sound — interaction acknowledgment |
| `death` | Any exchange that declares `arrivalSound: "death"` | Seven-note descending arpeggio (G5 down to A3, ~600 ms) — pac-man closure |
| Wrong-button beep | Audience hits the abort side of a `start_button` audience-interactive | Two-tone descending square wave (A5 → A4) |

The press-time doot is the audience-interaction sound — it fires
on every valid press during a transmission (after the typing
lockout clears). It's distinct from the arrival doot, which only
plays on gate-style exchanges where there's no body / no TTS to
carry the audio.

The default arrival-sound rules are:

- Body empty (gate) → `doot` (the arrival chirp announces the
  opening message)
- Anything with a non-empty body (INCOMING, OUTGOING, GAME OVER,
  custom) → silence by default. The TTS reading the body is the
  audio signal; an arrival chirp would step on its first words.
  Override with `arrivalSound` if you want a specific sound — e.g.
  GAME OVER beats set `"death"`.

Override per-exchange with the optional `arrivalSound` field
(`"doot"` / `"death"` / `"none"`).

**Text-to-speech** — transmission bodies and reply echoes are
spoken aloud through `AVSpeechSynthesizer`:

| When | Voice | What it speaks |
|---|---|---|
| INCOMING exchange arrives | Female | The body (in parallel with the typing animation) |
| OUTGOING exchange arrives | Male | The body (in parallel with the typing animation) |
| Audience press lands on a non-silent reply | Male | The reply label — the `YOU SENT: <text>` echo, voiced as "you" speaking |
| Silent choices (parens-wrapped), DELETE, gate, GAME OVER, custom headers | none | — |

Voice resolution is two-stage. First try a curated list of known
Apple voice identifiers (enhanced + compact variants of Samantha
/ Aaron / Tom / Alex, in that order). If none of those are
installed, enumerate `AVSpeechSynthesisVoice.speechVoices()` and
pick the first installed en-US voice matching the desired gender.
Last resort: the language-default voice. If even that fails the
TTS path silently no-ops rather than substituting the wrong
character voice.

For the reply echo specifically, the male voice gets a 200 ms
`preUtteranceDelay` so the press-time doot finishes before
speech starts — otherwise the doot smears the first syllable.

Speech is interrupted (`stopSpeaking(at: .immediate)`) on three
events:

- Audience press — they've moved past the message, voice goes
  with them
- Auto-advance fires — the next exchange's voice is about to
  start
- Lineup cursor moves — the bit is over

TTS routes through the system default audio output (not the
master mixer), so on a typical stage rig it travels the same
FOH path as the music — but the bed-level attenuation doesn't
apply. Tune via system volume or `AVSpeechUtterance.volume`.

**Schema**

```json
{
  "name": "Moving On",
  "kind": "transmission",
  "exchanges": [
    {
      "id": "open",
      "header": "NEW MESSAGE RECEIVED",
      "green": { "label": "READ", "next": "e1" },
      "red":   { "label": "DELETE", "next": "abort" }
    },
    {
      "id": "e1",
      "incoming": "how could you move on\nso fast",
      "green": { "label": "i had to", "next": "e2" },
      "red":   { "label": "(say nothing)", "next": "e2" }
    },
    {
      "id": "e3",
      "header": "OUTGOING",
      "incoming": "i'm finally finding happiness\n\ni hope you can too",
      "autoAdvance": { "holdSeconds": 7, "next": "e4" }
    },
    {
      "id": "e5",
      "incoming": "how can you do this to me",
      "autoAdvance": { "holdSeconds": 9, "next": "abort" }
    },
    {
      "id": "gameover",
      "header": "GAME OVER",
      "incoming": "YOUR RELATIONSHIP IS OVER\n\nYou cannot replay",
      "arrivalSound": "death",
      "autoAdvance": { "holdSeconds": 9, "next": "abort" }
    }
  ]
}
```

| Field | Meaning |
|-------|---------|
| `id` | Required. Unique within the script. Referenced by other exchanges' `next` fields. |
| `header` | Optional. Small dim text above the message body — `"INCOMING"` (default), `"OUTGOING"`, `"NEW MESSAGE RECEIVED"`. On gate-style exchanges (empty `incoming`) the header is rendered as a large centerpiece instead of a top label. |
| `incoming` | Optional. Body text. `\n` line breaks render as visible breaks; blank lines between thought-fragments stay visible. Default empty (signals a gate). |
| `green` / `red` | Optional. Reply choices on each button. Both must be present together, **or both absent**. Mutually exclusive with `autoAdvance`. Each has `label` (the visible reply text — wrap in parens for silent stage-direction style) and `next`. |
| `autoAdvance` | Optional. `{ "holdSeconds": <number>, "next": <id-or-abort> }`. After typing finishes, the body holds for `holdSeconds`, then transitions to `next`. No audience interaction. Mutually exclusive with `green`/`red`. |
| `arrivalSound` | Optional. `"doot"` / `"death"` / `"none"`. Overrides the default arrival SFX for this exchange. Default rules: `doot` for plain `INCOMING` messages with a body, `none` for everything else. |
| `next` | Either an exchange `id` (continues the script) or the literal `"abort"` (ends the bit). On a choice's `next: "abort"` the screen briefly shows `DELETED` before the lineup advances; on an `autoAdvance.next: "abort"` the lineup advances silently (the bit is ending on its own clock, not being deleted). |

**Pacing constants** (in `Sources/BackTrack/AudienceInteractive.swift`):

- `TransmissionPacing.charDuration` — typing reveal speed,
  default 0.04 s per character.
- `KeyboardHandler.transmissionEchoSeconds` — `YOU SENT: …`
  duration, default 1.0 s.
- `KeyboardHandler.transmissionPreIncomingSeconds` — blank
  between echo and next incoming, default 0.7 s.
- `KeyboardHandler.transmissionDeletedFlashSeconds` — DELETED
  flash on a manual abort press, default 0.8 s.

**Operator escape hatch**: `←` / `→` / `Space` all advance the
lineup mid-transmission, regardless of phase. Useful if it stalls
live or the audience freezes up.

**Self-care**: there's no runtime "skip tonight" toggle — if a
transmission doesn't fit a particular show, just remove it from
that night's setlist. The pieces are opt-in per show.

### Adding a new kind

The point of having a separate top-level lineup type for this is
that a new audience moment is a localized change. To add one:

1. Add a case to `AudienceInteractiveKind` (`Sources/BackTrack/AudienceInteractive.swift`).
2. Add a render branch in `AudienceInteractiveView.body` for the
   on-screen content (some kinds will have multiple phases — see
   `transmissionView` for an example).
3. Add cases in `KeyboardHandler.handleAudienceInteractiveGreen`
   and `handleAudienceInteractiveRed` for the per-button behavior.
4. Optional: extend `KeyboardHandler.toggleTransport`'s
   `.audienceInteractive` branch if `Space` should mirror a
   different button than green for that kind.
5. Any per-kind fields go on `AudienceInteractiveJSON` (the raw
   schema) and `AudienceInteractive` (the compiled struct), and
   the loader's `compile` switch should produce them.
6. For multi-step kinds: add a phase enum + `@Published`
   field on `AppState`, and reset it in
   `KeyboardHandler.selectLineupItem`'s teardown block.

The `AudienceInteractiveKind(rawValue:)` parser auto-picks up new
cases — no separate switch list to keep in sync.

## Setlists

Songs, countdowns, interstitials, and audience interactives are
arranged into ordered setlists for live use. The "lineup" — what
`←` and `→` actually navigate — is whichever setlist is currently
active. With no setlist active, the lineup falls back to all songs,
then all countdowns, then all interstitials, then all audience
interactives.

```
~/BackTrack/Setlists/01_full_show.json
```

### Schema

```json
{
  "name": "Full Show",
  "items": [
    { "kind": "countdown",            "ref": "Pre-show" },
    { "kind": "audience-interactive", "ref": "Start Show" },
    { "kind": "interstitial",         "ref": "Welcome" },
    { "kind": "song",                 "ref": "Get Yourself Together" },
    { "kind": "countdown",            "ref": "Intermission" },
    { "kind": "song",                 "ref": "Listen to the Dead" }
  ]
}
```

Valid `kind` values: `"song"`, `"countdown"`, `"interstitial"`,
`"audience-interactive"`. `ref` matches the `name` field on the
corresponding JSON file. References that don't resolve surface in
the HUD's issues block — the setlist still loads and plays
everything that does resolve.

### Switching setlists

`D` cycles through setlist files alphabetically. The HUD shows the
active setlist's name + your position (e.g. `SET   Full Show   3 / 12   →  GET YOURSELF TOGETHER`).
Cycling stops any in-flight playback and resets the cursor to item 0
of the new setlist.

To order setlists at the venue, prefix them numerically:
`01_saturday.json`, `02_acoustic.json`, etc. Then `D` lands on the
right one with one or two presses.

### Transport between items

When a song reaches its last bar (or a countdown hits 0:00), playback
**stops** and the cursor advances to the next item, but does not
auto-start. The next Space starts the next item. Live performers
want a beat between songs.

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

The runtime surface is intentionally small — songs, countdowns, and
setlists are configured in JSON, not at the venue. Every key here is
about navigating that pre-built structure.

| Key | Action |
|-----|--------|
| `Space` | Start / stop |
| `←` / `→` | Previous / next lineup item (stops playback) |
| `↑` / `↓` | Next / previous part. Wraps around (up from last part → first). While stopped: immediate; Space starts from the selected part. While playing: queued to next bar; repeated presses accumulate. |
| `L` | Toggle loop-current-part — disables auto-advance so the part repeats indefinitely. |
| `D` | Cycle the active setlist alphabetically (no-op with 0 or 1 setlists). Stops in-flight playback, rebuilds the lineup, and resets to item 0 of the new setlist. |
| `V` | Show / hide the visuals window. |
| `F` | Toggle the visuals window into macOS native full-screen (title bar auto-hides, window covers the display). Opens the window first if it was closed. |
| `\` | Toggle **tweak mode** — see below. |
| `1` | **Audience green button.** During a song: cycle a 10-second post-effect (`glitch` → `tracking` → `chroma`) over the part's JSON `visualEffect`, with a half-second white-flash for feedback. During a countdown: cycle render style (digital / pie / hourglass). On a `start_button` audience-interactive: advance the show. Suppressed during videoClips. See [Audience interaction](#audience-interaction). |
| `2` | **Audience red button.** During a song: tap to toggle a full-screen amber-on-black `TELEMETRY` panel that takes over the visuals window; auto-hides after 5 s, or tap again to dismiss early. During a countdown: tap to advance the rotating message. On a `start_button` audience-interactive: error beep + "WRONG BUTTON" flash. Suppressed during videoClips. See [Audience interaction](#audience-interaction). |

Songs, countdowns, setlists, and `patterns.json` auto-reload within
~1 s of being saved. Sample folders only load at launch — restart
the app to pick up new kits.

## Audience interaction

Two keys are intended to be triggered by audience members rather than
the performer: `1` (green button) and `2` (red button), wired to
physical buttons in front of the audience. Both are no-ops while a
`videoClip` is playing — the clip owns the screen and an
audience-triggered effect would step on a deliberate musical /
comedic moment. Most overrides also reset when the lineup cursor
moves to a new item.

> **Wiring note.** On this rig, the **green** physical button is
> wired to send key `1`, and the **red** physical button sends key
> `2`. The handlers are named after the *button color the audience
> sees*, so `handleAudienceInteractiveGreen` runs from key `1` —
> not key `2` — by design. Don't "fix" this without checking the
> hardware first.

### During a song

- **`1` — temporary post-effect.** Each press cycles to the next of
  `glitch` / `tracking` / `chroma` (skipping `none` so every press
  is visibly *something*). The override sits on top of the part's
  JSON `visualEffect` for ~10 seconds, then auto-reverts to whatever
  the JSON says — audience-triggered effects always feel like a
  "moment", not a takeover. Rapid presses cancel-and-rearm the timer
  so a tap-tap-tap walks through the cycle without timing out
  mid-walk. Each press also fires a half-second white flash over the
  entire visuals window (rendered above the post-effect layer so the
  flash itself isn't glitched) as unambiguous "your press
  registered" feedback.
- **`2` — telemetry toggle.** Each tap flips the visuals window
  between the song's normal output and a full-bleed 1:1 amber-on-
  black `TELEMETRY` panel that ignores the song's theme. The panel
  renders ~20 lines of live data: set / song / bar progress bars
  (three time scales), 4-dot beat indicator, current and next chord,
  kit + pattern, decaying level meters with firing dots for kick /
  snare / hh / pad / bass, and the active visualizer / theme / FX
  (with an "Xs remaining" countdown when an FX override is in
  flight). The panel auto-hides after 5 seconds, or a second tap
  dismisses it early. Tap-toggle (rather than press-hold) because
  the audience hardware buttons only signal on press. See
  [Telemetry panel](#telemetry-panel-audience-toggle) in the Visuals
  window section for the full layout.

### During a countdown

- **`1` — render-style cycle.** Cycles through `digital` / `pie` /
  `hourglass` indefinitely; the override persists until the lineup
  cursor moves.
- **`2` — message advance.** Bumps a manual offset on top of the
  time-based message index, so each tap immediately reveals the next
  entry in the countdown's `messages` array without waiting for the
  interval boundary.

### During an audience-interactive item

[Audience interactives](#audience-interactives) are the fourth
lineup-item kind, designed entirely around these two buttons. Each
audience-interactive `kind` defines its own per-button semantics,
documented in that section. For the currently shipped `start_button`
kind:

- **`1` — advance** (the green button on this rig). Moves to the
  next lineup item.
- **`2` — wrong choice** (the red button). Plays an 8-bit two-tone
  error beep through the audio engine and shows "WRONG BUTTON" in
  red for ~1.5 s.
- **`Space`** — mirrors the advance action (key `1`) so the operator
  can drive the show from the keyboard if the audience freezes up.

### Suppression rules

- Both keys are silently consumed when they have no work to do (on
  interstitials, when no item is current, in tweak mode, mid-
  videoClip). They never propagate to AppKit, so a press that does
  nothing also does nothing — no macOS alert beep on stage.
- Both are suppressed during a `videoClip` on a song.
- The `1` key during a song (effect cycle) is also suppressed while
  the telemetry panel is up — the takeover owns the screen.
- All overrides reset when `←` / `→` moves the lineup cursor — the
  telemetry panel hides, any pending auto-hide is cancelled, and the
  audience-effect override is cleared.
- OS key-repeat is ignored on `2` so a stuck key can't toggle the
  telemetry panel on/off rapidly.

## Tweak mode

A structured, in-app editor for the parameters you'd most often want
to adjust on an existing song — kit, sounds, theme, visualizer,
count-in, plus per-part pad/bass complexity and visual settings.
Everything writes back to the song's JSON file on every change, so
the JSON stays the source of truth.

Tweak mode is **not** a song authoring tool. Chord progressions,
lyrics, drum patterns, repeats, and the parts/structure remain
JSON-edited — the editor is for "tweak and finalize," not "make
something from scratch."

Press `\` to toggle. Works whether transport is stopped or playing —
cycling values mid-playback so you can hear them land is the intended
workflow.

### Editable fields

| Scope | Field | Cycles through |
|-------|-------|----------------|
| Song | `kit` | folder names under `~/BackTrack/Samples/drums/` |
| Song | `padSound` | folder names under `pads/` (plus `(none)` only if no part uses pad) |
| Song | `bassSound` | folder names under `bass/` (plus `(none)` only if no part uses bass) |
| Song | `theme` | `dark` / `light` |
| Song | `visualizer` | the nine visualizer styles |
| Song | `countIn` | 0–4 bars |
| Part | `pattern` | every drum pattern in `patterns.json` (alphabetical) |
| Part | `padLevel` | 0–3 |
| Part | `bassLevel` | 0–3 |
| Part | `visuals` | every file in `~/BackTrack/Visuals/`, plus `(none)` |
| Part | `visualMode` | `bar` / `beat` |
| Part | `visualizer` | the nine styles, plus `(use song default)` |
| Part | `visualEffect` | `none` / `glitch` / `tracking` / `chroma` |
| Part | `videoClip` | every file in `~/BackTrack/VideoClips/`, plus `(none)` |
| Part | `videoClipVolume` | `0%` / `25%` / `50%` / `75%` / `100%` / `110%` / `120%` |

Cycling is bounded — you can never land on an invalid value. The
`(none)` stop on `padSound` / `bassSound` is suppressed when any
part of the song has a non-zero `padLevel` / `bassLevel`, since
saving with no song-level sound name in that case would cause the
song to fail to reload.

### Keybindings (in tweak mode)

| Key | Action |
|-----|--------|
| `↑` / `↓` | Move the cursor between fields |
| `←` / `→` | Cycle the focused field's value backward / forward |
| `[` / `]` | Same as `←` / `→` |
| `Space` | Toggle transport (live preview) |
| `L` / `V` / `F` | Loop / visuals window / full-screen — same as performance mode |
| `\` | Exit tweak mode |

`D` (cycle setlist) and lineup navigation are intentionally
suppressed in tweak mode — exit first to navigate songs.

### Save behavior

Every cycle is auto-saved to disk via `SongLoader.save()` (sorted
keys, default-fields-omitted, deterministic diff). A toast at the
bottom of the field list confirms the write, e.g. `saved → kit: 808`.

`kit`, `padSound`, and `bassSound` cycles also tell the audio engine
to swap its loaded buffers immediately, so the next drum / pad / bass
trigger uses the new sound — no need to stop and restart playback.
Other fields (levels, visuals, theme, etc.) are read live from the
song struct on every tick / render frame, so they're already live.

## HUD

Two-column layout, 1000×560. The left column is stable (performance
info that can't shift); the right column holds the variable-length
song header + lyrics so long verses don't push the left-column
readouts around.

**Left column:**

- **Structure**: all parts in play order, current one wrapped in `▸ ◂`. Wraps to multiple lines for long structures.
- **Bar counter**: `bar N / M` plus a one-cell-per-bar progress bar (`█░░░`) so remaining bars in instrumental sections are glanceable.
- **Chord line**: current chord large (40pt), next bar's chord dim to the right, and four 1 / 2 / 3 / 4 beat dots on the right that track the current beat so you can come in on the one.
- **Mix**: three rows, one per role. `DRUMS` shows the current pattern + kit; `PAD` / `BASS` show the active sound. Each row has its own activity light (drums light fires on any kick / snare / hh hit).
- **Loop badge**: when loop-current-part is on (`L` toggle), a bright `LOOP` appears in the structure header.
- **Transport**: `● PLAYING` / `○ STOPPED`.
- **Issues**: `MISSING SAMPLES` and `SONG ISSUES` blocks appear when files are missing or a song file fails to parse.
- **Keybindings**: a five-row grid covering every shortcut, including the audience-button row (`1` / `2`).

**Right column:**

- **Song header**: name, key, tempo.
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

The shipped library ships 35 patterns, indie-rock-leaning:

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
| Hats only | Quarter-note hats, no kick or snare — ambient pulse |
| Hats 8ths | 8th-note hats, no kick or snare — driving texture |
| Hats 16ths | 16th-note hats, no kick or snare — shimmer |
| Hats poly | Dotted 3-3-3-3-2-2 hat polyrhythm, no kick or snare |
| Pure kick | Four-on-floor kick, no hats or snare — primal pulse |
| Heartbeat | Paired kick hits on 1 & 1+, then 3 & 3+ — organic |
| Snare march | Quarter-note snare, no kick or hats — military |
| Hats + backbeat | Snare 2&4 + 8th hats, no kick — atmospheric verse |
| Old-school | Kick 1&3 + snare 2&4, no hats — 60s rock feel |
| One-drop | Kick & snare together on beat 3, offbeat hats — reggae |
| Punk drive | 8th-note kicks + snare 2&4 + 8th hats — fast & aggressive |
| Trip-hop | Half-time kick + ghost snare, ghosted 8th hats |
| Long build | Snare ramp 8th→16th with hat acceleration — extended fill |
| Silent | No drum hits at all — for parts that should be drum-free (pad / bass / vocals only) |

Edit the file to customize any of them or add your own. Auto-reloads
on save (within ~1 s).

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

### Video clips (with audio)

A second media path on each part: drop files into `~/BackTrack/VideoClips/`
(directory is created on first launch), then reference them per part
via `videoClip` + optional `videoClipVolume` (see Songs schema above).

Differences vs. the visuals layer:

- Plays **once** with audio, start to finish
- Volume is per-part-configurable, defaults to 100%
- Overrides everything else in the visuals window for the duration
  of the clip
- When the clip finishes mid-part, the visuals window falls back to
  whatever the part normally would show (GIF / synth)
- The backing track keeps playing alongside the clip's audio — to
  silence the backing track during the clip, set the part's
  `padLevel: 0`, `bassLevel: 0`, and `pattern: "Silent"`

**Mix dynamic.** The whole backing track (drums + pad + bass) runs
through a master mixer pinned at `0.5` (-6dB). Video clips play
through their own `AVPlayer` at unity, so they sit naturally on top
of the bed without any auto-ducking. A constant bed (vs. ducking
during clips) means musical moments where the clip *is* the song's
accent — not a comedic break — keep their full intensity. If a clip
still feels buried, bump `videoClipVolume` per part; if it's
clipping over the bed, drop it.

Stop / part change / song change tears the clip down. Looping a part
with a videoClip plays the clip once on the first loop only.

Same supported extensions as the visuals layer's video files.
Restart the app to pick up new files in the directory.

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

### Telemetry panel (audience toggle)

When the audience taps the red button (`2`) during a song, the
visuals window's normal output is replaced by a full-screen
amber-on-black `TELEMETRY` readout for ~5 seconds, after which it
auto-hides; tapping again before the timer dismisses early. The
panel ignores the song's theme — amber-on-black always — and
ignores the active post-effect, the audience flash, GIFs, and the
synth layer; it's a system overlay, not a song layer.

The panel is a single monospaced text block, rendered via
`TimelineView` so every field updates each animation frame in sync
with the audio. It's centered as a 1:1 square inside whatever aspect
ratio the visuals window is running at; the non-square bezels are
rendered black so the framing reads as CRT housing, not letterboxing.

Fields, top-to-bottom:

- `SET` — overall lineup progress as `[████░░░░] 33% (4/12)`.
- `SONG` / `KEY` / `BPM` / `STATE` — invariants of the current item
  plus playing/stopped.
- `PROG` — song progress, computed by summing the bar-counts of
  completed parts plus the current bar in the active part, divided
  by the song's total bars.
- `PART` — current part name and `(idx/total)`.
- `BAR` — `[████░░░░] N/M` for the current bar within the active
  part.
- `BEAT` — four `○ ○ ● ○`-style dots, one filled at the current
  beat (mirrors the HUD's beat dots).
- `CHORD` — `current → next` chord display.
- `PATTERN` / `KIT` — drum pattern + kit names.
- Five instrument rows — `KICK` / `SNARE` / `HH` / `PAD` / `BASS`.
  Each shows a 22-char level meter that decays linearly from full to
  empty over a per-instrument decay window after each trigger, plus
  a binary `◉` / `◯` "currently firing" dot. `PAD` and `BASS` rows
  append the part's `L0`–`L3` complexity.
- `VIZ` / `THEME` — active visualizer style and theme.
- `FX` — active post-effect; if a song-effect override is in flight,
  the line reads `FX glitch (override · 7s)` with the seconds
  counting down live.

The panel is suppressed during videoClips. It does not appear on
countdowns or interstitials — both audience keys do other things in
those contexts (see [Audience interaction](#audience-interaction)).

Everything else is sized proportionally to `min(width, height)` so
it holds up on any aspect ratio. Toggle the whole window with `V`;
full-screen with `F`.

## Files

- `App.swift` — entry point, coordinator wiring (loads songs / countdowns / interstitials / audience interactives / setlists)
- `AppState.swift` — observable state (songs, transport, lineup, audience-button overrides, wrong-button flash, telemetry visibility)
- `AudienceInteractive.swift` — AudienceInteractive struct + AudienceInteractiveKind enum + transmission script types (TransmissionScript / Exchange / Choice / AutoAdvance / Next / Phase) + JSON schemas + shared TransmissionPacing constants (typing reveal speed, etc.)
- `AudienceInteractiveLoader.swift` — directory scan + validation for audience-interactive JSON files (lenient on hyphens/underscores in `kind`); compiles + validates transmission `exchanges` (unique ids, both-or-neither choices, autoAdvance↔choices mutual exclusion, every `next` resolves)
- `AudienceInteractiveView.swift` — full-screen audience-driven screen; per-kind branches: start_button (themed prompt + WRONG BUTTON overlay), transmission (phosphor-green CRT terminal — gate centerpiece, character-by-character typing with layout-stable underlay, stacked reply prompts gated on typing-complete, DELETED flash on manual abort)
- `AudioEngine.swift` — AVAudioEngine graph, sample loading, pitched voice pools, master-mixer bed level, dedicated SFX node feeding the master mixer (wrong-button beep, transmission "doot doot" message-received chirp, pac-man-style "death" arpeggio for GAME OVER beats — all synthesized once at startup), and an AVSpeechSynthesizer for transmission TTS (female INCOMING / male OUTGOING, resolved at startup from a fallback chain of known voice identifiers)
- `AudioDevices.swift` — CoreAudio helpers for default output device name
- `ChordParser.swift` — chord symbol → root pitch class + quality + 7th
- `Clock.swift` — 16th-note timer, song playback engine
- `ContentView.swift` — SwiftUI HUD (with audience-interactive deck + header blocks)
- `Countdown.swift` — Countdown / CountdownStyle / CountdownTransport structs + JSON schema
- `CountdownLoader.swift` — directory scan + validation for countdown JSON files (rawValue-driven style parser)
- `CountdownView.swift` — full-screen countdown display (digital / pie / hourglass), label + rotating message + colored-dot audience-button prompt
- `FileWatcher.swift` — ~1 s polling reloader for songs / countdowns / interstitials / audience interactives / setlists / patterns.json
- `Generators.swift` — drum pattern loader, pad + bass generators
- `IdleStaticView.swift` — TV static / "no signal" idle state, shown when transport is stopped with no part-level visual
- `Interstitial.swift` — Interstitial struct + JSON schema (text / image / video kinds)
- `InterstitialLoader.swift` — directory scan + validation for interstitial JSON files (rawValue-driven kind + theme parsers; theme parser shared with SongLoader)
- `KeyboardHandler.swift` — NSEvent local monitor (keyDown only; audience presses unconditionally consumed to suppress the macOS alert beep), tap-toggle telemetry timer, song-effect cycle timer, transmission state machine + auto-transition timers, audience-interactive routing per kind
- `LyricsVisualizers.swift` — NSViewRepresentable auto-fitting justified-text view, plus the centered single-line/word view
- `PostEffect.swift` — PostEffect enum (none / glitch / tracking / chroma) + shared rawValue-driven parser
- `PostEffectsView.swift` — implementations of the glitch / tracking / chroma post-processing layers
- `Setlist.swift` — Setlist struct + JSON schema (ordered refs to song / countdown / interstitial / audience-interactive)
- `SetlistLoader.swift` — directory scan + ref-resolution against songs / countdowns / interstitials / audience interactives
- `Song.swift` — Song / Part structs + raw JSON schema; VisualizerStyle (incl. `oscilloscope`) + VisualTheme enums
- `SongLoader.swift` — directory scan + validation; rawValue-driven shared visualizer + theme parsers
- `TelemetryView.swift` — full-screen amber-on-black telemetry panel toggled by audience taps on `2` during a song (auto-hides after 5 s)
- `Tweak.swift` — TweakField enum + cycling logic for the in-app structured editor
- `VideoClipView.swift` — AVPlayer-backed view for `videoClip` parts and video interstitials, with volume + loop awareness
- `VisualView.swift` — NSViewRepresentable for images / GIFs (via NSImageView) and video (via AVPlayer), all with CSS-cover scaling
- `VisualsView.swift` — Canvas-based synth-layer visuals window, geometric + lyric + oscilloscope motifs, audience-interactive + telemetry takeovers, audience-flash overlay
