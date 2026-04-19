# chess openings

an ios app for drilling chess opening lines. pick an opening, pick a line,
play it move-by-move against the book until it sticks.

## what it does

the app ships with a catalogue of well-known openings (italian game, ruy
lopez, scotch, vienna, king's gambit, danish gambit, london system, queen's
gambit, caro-kann, scandinavian, french, sicilian, king's indian,
nimzo-indian, queen's gambit declined, slav). for each opening it provides
multiple concrete lines — the variations you actually see in play — and
lets you practise them as either white or black.

each line is a sequence of plies (half-moves). the drill engine plays the
book reply after your move, so you only have to think about your side. if
you play the right move the board advances; if you play the wrong move
you either get the piece snapped back (strict mode) or shown the book
reply and given a chance to retry (show-and-retry mode).

## features

- **two drill modes**
  - strict: wrong moves bounce back, no feedback
  - show-and-retry: the book move is revealed after a mistake so you can
    replay it correctly
- **mastery tracking**: each line records a correct-streak. hit the
  mastery threshold (default 3) without mistakes and the line is marked
  learned. per-line progress persists between sessions.
- **hint and solution buttons**: hint highlights the source square of
  the next book move; solution highlights source and destination.
- **undo / reset**: undo steps back to the last position you were
  prompted from (skipping over scripted replies and black-side autoplay);
  reset returns to the starting position.
- **board sounds**: chess.com-style sfx for moves, captures, castles,
  promotions, and checks, with a separate "opponent move" sound for
  scripted replies. togglable in settings.
- **dual-source lines**: every opening is seeded from two lichess
  explorer sources — masters database (games ≥50) and online 2200-2500
  blitz/rapid/classical (games ≥500). lines are grouped by source in
  the opening detail view so you can see what the top humans prefer vs.
  what strong online players actually play.
- **custom library**: create your own openings and lines alongside the
  seeded ones; seed reloads only wipe seeded entries, custom entries
  survive app updates.
- **black-side autoplay**: when you're drilling a black-side opening,
  the app plays white's first move for you so the board is already
  waiting on your reply.
- **rolling mistake log**: the last 20 mistakes per line are kept for
  future review features.

## architecture

swiftui + swiftdata app targeting ios. one binary, one scheme, one
persistence store.

### layout

```
chess openings/
├── core/
│   ├── chess/       ChessTypes, Side, SanCodec, PositionBuilder
│   ├── drill/       DrillSession, DrillMode, DrillStatus, DrillProgress,
│   │                BookPly, BookCandidate, LineSource, MoveOracle,
│   │                LineBookOracle
│   └── audio/       AudioService, SoundEffect
├── data/
│   ├── models/      Opening, Line, LineProgress, UserSettings, Mistake
│   └── seed/        SeedLoader, SeedDTO
├── views/
│   ├── board/       BoardView, SquareView, HighlightKind,
│   │                PromotionPickerView
│   ├── train/       OpeningListView, OpeningDetailView, DrillView
│   ├── library/     LibraryListView, NewOpeningView, LineEditorView
│   ├── settings/    SettingsView
│   └── shared/      FlowLayout, ProgressBarView
├── resources/       openings.json (seed), Sounds/*.mp3
└── chess_openingsapp.swift
```

### key pieces

- **`DrillSession`** (`core/drill/DrillSession.swift`) — the drill state
  machine. holds a `ChessKit.Board`, the user's history, a parallel
  `historyByUser: [Bool]` audit (so undo can skip over autoplay/reply
  moves), and a `DrillStatus` (`waitingForUser` / `evaluating` /
  `mistake` / `lineComplete`). `submit(move)` compares the user's move
  against the `MoveOracle`, applies the scripted reply, and updates
  streak + status. onmoveapplied callback fans out to the audio layer.
- **`MoveOracle`** (`core/drill/MoveOracle.swift`) — strategy protocol
  for "what moves does the book accept here?". the default
  implementation, `LineBookOracle`, is a pure lookup against the line's
  ply list. swapping in a fuzzier oracle (e.g. "any main-line
  transposition") is a one-type change.
- **`SeedLoader`** (`data/seed/SeedLoader.swift`) — reads
  `resources/openings.json`, validates every ply by replaying it
  through a `ChessKit.Board`, and upserts into swiftdata. re-runs are
  idempotent: a version bump in the json wipes all rows with
  `isSeed == true` (cascading to lines and progress) and re-imports.
  user-created openings (`isSeed == false`) are never touched.
- **`AudioService`** (`core/audio/AudioService.swift`) — lazy
  per-effect `AVAudioPlayer` cache over 14 chess-style sfx. the sound
  category is set to `.ambient` so the app mixes politely with music.
- **swiftdata models** — `Opening` has many `Line`s (cascade delete).
  `Line` stores plies as json-encoded `Data` (swiftdata doesn't handle
  arbitrary codable arrays natively) and has an optional `LineProgress`
  (1:1) and a `LineSource` (masters / open). `UserSettings` is a
  singleton row carrying drill mode, mastery threshold, sounds toggle,
  and `seededVersion` for seed migrations.
- **`ChessKit`** is the only third-party swift dep. it handles san
  parsing, move legality, and board state.

### seed pipeline

the built-in openings under `resources/openings.json` are generated by a
perl script, not hand-written.

- **`scripts/seedbuilder/seed-catalogue.json`** — per-opening config:
  name, eco code, side, root san sequence, and desired line count.
- **`scripts/seedbuilder/build-seed.pl`** — walks each opening through
  the lichess explorer api (both `/masters` and `/lichess` with
  2200-2500 blitz/rapid/classical filter) following the most-played
  reply at each ply until the line hits 10-20 plies or game-count drops
  below the threshold (50 masters / 500 online, with softer floors for
  early plies). md5-keyed disk cache avoids re-fetching during
  iterative runs. output is atomic (write-to-tmp + rename) and requests
  have exponential-backoff retry for 429s and 5xx.
- **`scripts/seedbuilder/annotations.json`** — optional per-ply text
  notes that get merged into the generated seed if the san matches.
- **`scripts/seedbuilder/check-seed.pl`** — sanity check that every
  opening has at least one line from each source and that plies stay
  within range.

the schema version (`SeedDTO.version`) is bumped whenever the catalogue
or structure changes; the next app launch notices the bump and re-seeds.

## build & test

all builds and tests go through the makefile at the repo root so the
scheme and simulator destination are defined once.

```
make build                                # compile
make test-all                             # all xctests + ui tests
make test T="Chess OpeningsTests/DrillEngineTests"
make test T="Chess OpeningsTests/DrillEngineTests/test_drillsession_undo_steps_back_one_full_move"
make clean
```

default destination is `iPhone 16 Pro`; override with `DESTINATION=...`.

### tests

- `ChessCoreTests` — san parsing, position construction, side bridging,
  seed dto decoding
- `DrillEngineTests` — drill session transitions: strict vs
  show-and-retry, undo semantics, autoplay, streak increment, move
  applied callbacks
- `AudioTests` — sound classifier + mute behaviour
- `SeedLoaderVersionTests` — idempotent seed, wipe-on-version-bump,
  user-opening preservation
- `SeedIntegrityTests` — every seeded line validates move-by-move and
  covers both sources

## regenerating the seed

```
perl scripts/seedbuilder/build-seed.pl   # writes chess openings/resources/openings.json
perl scripts/seedbuilder/check-seed.pl   # sanity check
```

put a lichess api token in `lichess-api-key.txt` at the repo root to
raise the explorer rate limit (file is gitignored). without a token the
script falls back to anonymous requests with a 1s delay between calls.
