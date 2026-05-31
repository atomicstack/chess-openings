# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & test

All builds and tests go through the Makefile at the repo root — never invoke `xcodebuild` directly. The scheme, project, and simulator destination are defined once there.

```
make build                                                    # compile only
make test-all                                                 # full XCTest + UI suite
make test T="Chess OpeningsTests/DrillEngineTests"            # subset by suite
make test T="Chess OpeningsTests/DrillEngineTests/test_X"     # single test
make clean
```

Default destination is `iPhone 16 Pro`; override with `DESTINATION=...`. `XCB` wraps `xcodebuild` with `taskpolicy -d throttle nice -n20` so a long build stays out of the foreground's way — keep that wrapper unless you need to debug build perf.

For physical-device deploys, use `xcodebuild -destination "platform=iOS,id=<UDID>" build` directly, then `xcrun devicectl device install app --device "<name>" <path>`.

## Project structure quirks

- **Synchronized root groups** (modern Xcode pbxproj feature) — adding or removing Swift files does NOT require `.pbxproj` edits. Drop a file under `Chess Openings/...` and it's picked up automatically. The same is true for arbitrary resources (the `Stockfish/` NNUE files at bundle root flow through this).
- **SPM packages DO require `.pbxproj` edits.** The existing `chesskit-swift` block at the bottom of `project.pbxproj` is the template — six touch points (XCRemoteSwiftPackageReference, XCSwiftPackageProductDependency, PBXBuildFile, Frameworks build phase, target's packageProductDependencies, project's packageReferences) all need a fresh 24-hex-char UUID. `chesskit-engine` was added this way; mirror it.
- **NNUE files (~74 MB total)** live in `Chess Openings/Resources/Stockfish/` and are checked into git. `EngineService.bundledNNUEPath` looks them up at the **bundle root** (no `inDirectory:` arg) because the sync-root-groups feature flattens them.

## High-level architecture

SwiftUI + SwiftData iOS app, single binary, single scheme. ChessKit (chess-rules) and ChessKitEngine (Stockfish UCI wrapper) are the only third-party deps.

### Two concurrent session machines

The app has two structurally parallel session types — read one to understand the other:

- **`DrillSession`** (`Core/Drill/`) — book-driven. Compares user moves to a `MoveOracle` (default `LineBookOracle` is a pure ply-list lookup). Status: `waitingForUser / evaluating / mistake / lineComplete`. `submit(move)` applies user move + scripted reply + updates streak.
- **`EnginePlayoutSession`** (`Core/Engine/`) — Stockfish-driven, kicks in after a drill line completes. Status: `waitingForUser / engineThinking / drawOffered(byUser:) / gameOver(GameOverReason)`. `submit(move)` applies user move, awaits an optional async `onUserMoveAnalysing` hook, then calls `playEngineReply()`.

Both keep a parallel `historyByUser: [Bool]` array so `undo()` can pop the right number of moves (user move + engine/scripted reply as a unit). Both fire `onMoveApplied(Move, pre: Position, post: Position, byUser: Bool)` so the audio layer can play sfx without coupling.

### Engine wrapper — single serialised queue

`EngineService` owns one `ChessKitEngine.Engine` instance. Stockfish's UCI protocol has a single shared response stream — concurrent `bestMove` / `evaluate` calls would race for `.bestmove` events. The `enqueue` helper chains all queries through one `Task<Void, Never>` in-flight pointer; each new caller awaits the previous chain tail. **All public methods must route through `enqueue`** — touching `engine.send(...)` directly bypasses the queue and can leak responses between callers. Initial NNUE setup is cached in `setupTask` so re-entrant `ensureReady()` calls don't double-init.

The `EngineServicing` protocol is fronted by `FakeEngineService` so tests run without booting a real Stockfish. The real smoke test (`EngineSmokeTests`) is gated by env-var `RUN_ENGINE_INTEGRATION=1` via `XCTSkipUnless` — env propagation through `xcodebuild` is unreliable, so the test is effectively manual-only.

### Move-quality analysis runs BEFORE the engine reply

In `EnginePlayoutSession.submit`, the async `onUserMoveAnalysing(move, pre, post)` callback is awaited between the termination check and `playEngineReply`. `DrillView` wires this callback to issue two `bestMove` / `evaluate` queries on the shared engine — they queue ahead of the gameplay reply. Order in the queue: analysis bestMove → analysis evaluate → gameplay reply. The reply is therefore delayed by the analysis time, but the move-quality badge appears first (matches lichess/chess.com UX expectations).

Brilliant-move detection is in `MoveQualityHeuristics.swift` — it composes chess.com's criteria (sacrifice + not-already-winning + still-winning-after + best-move + min-knight-value + lower-value-attacker) and only upgrades `.best` to `.brilliant` when `isBrilliantCandidate` is true.

### SwiftData persistence

`Opening` has-many `Line`s (cascade delete); `Line` has 1:1 optional `LineProgress`. Line plies are JSON-encoded `Data` because SwiftData doesn't handle arbitrary `Codable` arrays natively — `Line.plies` exposes a computed `[BookPly]` over `pliesData`. `UserSettings` is a singleton-by-convention row.

**Persistence wiring**: `DrillSession+Persistence.swift` exposes `attachProgressTracking(line:threshold:context:)` that **composes** onto pre-existing `onLineComplete` / `onIncorrectMove` callbacks (captured as `priorComplete` and re-invoked after the persistence step). `DrillView.startSessionIfNeeded` wires audio first, then persistence — order matters because composition wraps the prior callback.

### Seed pipeline

`Chess Openings/Resources/openings.json` is generated by a Perl script under `Scripts/SeedBuilder/`, not hand-written. `SeedDTO.version` bumps on schema or content changes; `SeedLoader` re-seeds idempotently — wipes `isSeed == true` rows (cascading), preserves `isSeed == false` user-created entries.

To regenerate:

```
perl Scripts/SeedBuilder/build-seed.pl
perl Scripts/SeedBuilder/check-seed.pl
```

Lichess API token goes in `lichess-api-key.txt` at the repo root (gitignored) to raise the explorer rate limit.

## chesskit-swift API gotchas

- `Square(_ String)` is **non-failable** — malformed notation silently snaps to `.a1`. Always validate (`a-h` file + `1-8` rank) before constructing. `EnginePlayoutSession.isAlgebraicSquare` and `DrillView.isAlgebraic` are the existing local validators.
- **Promotion is two steps and easy to get wrong** — see the dedicated section below. This bug has now shipped twice; the regression suite is `EnginePlayoutSessionPromotionTests`.
- `Move` initialiser is `Move(result: .move, piece: …, start: …, end: …)`. UCI parsing in playout deliberately rejects 5-char promotion strings (e.g. `e7e8q`) — engine-side promotion handling is a known v1 limitation.

### Promotion: two-step or you'll ship the bug a third time

`Board.move(pieceAt:to:)` **does NOT commit a promotion**. When a pawn reaches the final rank it half-applies the move:

- `board.state` parks at `.promotion(pendingMove)`,
- the position toggles side-to-move,
- the pawn occupies the final rank as a pawn (NOT a queen/knight/whatever),
- `board.move(...)` returns the pending `Move?` you must hand to `completePromotion`.

To fully commit, the calling code MUST follow up with `board.completePromotion(of: pending, to: kind)`. The user's piece choice arrives in `move.promotedPiece?.kind` (set by `BoardView.completePromotion` after the picker sheet).

Every helper that applies moves to a `Board` must follow this two-step pattern:

```swift
let pending = board.move(pieceAt: move.start, to: move.end)
if case .promotion = board.state,
   let pending,
   let promo = move.promotedPiece {
    _ = board.completePromotion(of: pending, to: promo.kind)
}
```

This applies to:
- `DrillSession.apply` and `DrillSession.rebuildBoardFromHistory`
- `EnginePlayoutSession.apply` and `EnginePlayoutSession.rebuildBoardFromHistory`
- Any new session-shaped type that wraps a `ChessKit.Board`

**Symptoms of forgetting it** (you've reported this exact bug twice already):
- the user's pawn appears on the last rank but never becomes a queen,
- control mysteriously "swaps" to the opponent (side-to-move toggled but board is jammed),
- in playout, the engine never replies (`submit()`'s `if case .promotion = board.state { return }` safety net fires),
- in drill, replay-from-history produces the wrong position after a promotion ply.

If you're touching ANY code that calls `board.move(pieceAt:to:)`, ask: "could this move be a promotion?" If yes, you need the two-step. If you're not sure, write a test against a pawn-on-7th FEN before changing anything.

## License note

Stockfish is GPL-v3. Bundling it pulls the app under GPL-compatible obligations. There's well-known unresolved tension between GPL-3 and App Store ToS — many Stockfish-bundling iOS apps ship anyway. Full license at `Chess Openings/Resources/Stockfish/LICENSE-stockfish.txt`.
