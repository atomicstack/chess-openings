import XCTest
import ChessKit
@testable import Chess_Openings

/// Regression coverage: the user reported that `capture.mp3` only fires
/// when the player captures, not when the engine captures. Root cause is
/// that `EnginePlayoutSession.parseUCI` constructs `Move(result: .move,
/// piece: ..., start: ..., end: ...)` — `.move`, not `.capture(piece)`.
/// `SoundEffect.forMove` keys the capture sound off `move.result ==
/// .capture(...)`, so engine captures fall through to the plain
/// `.moveOpponent` sound. The same defect also silences the engine's
/// check sound (`Move.checkState` is never populated on the
/// `parseUCI`-built move).
///
/// These tests exercise the move-result and check-state metadata that
/// gets forwarded to `onMoveApplied` for engine moves, *not* the audio
/// pipeline itself, so they're independent of `AudioService` wiring.
@MainActor
final class EnginePlayoutSessionMoveResultTests: XCTestCase {

    /// Engine (black) recaptures on the e4 pawn via bootstrap.
    /// Expected: the move forwarded to `onMoveApplied` carries
    /// `.capture(...)` so `SoundEffect.forMove` returns `.capture`.
    func test_engine_capture_is_classified_as_capture_sound() async throws {
        // black to move; d5xe4 is the only sensible capture
        let fen = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
        guard let pos = Position(fen: fen) else {
            XCTFail("could not parse fen"); return
        }
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["d5e4"]
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )

        var capturedMove: Move?
        var capturedPre: Position?
        var capturedPost: Position?
        session.onMoveApplied = { move, pre, post, _ in
            capturedMove = move
            capturedPre = pre
            capturedPost = post
        }

        await session.bootstrap()

        let move = try XCTUnwrap(capturedMove, "engine reply never fired onMoveApplied")
        let pre = try XCTUnwrap(capturedPre)
        let post = try XCTUnwrap(capturedPost)
        let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: false)
        XCTAssertEqual(sfx, .capture,
                       "engine capture must produce the capture sound, got \(sfx)")
    }

    /// Engine (black) delivers Qh4# via bootstrap on the
    /// f3-e5-g4 fool's mate setup. Expected: the move forwarded to
    /// `onMoveApplied` carries a check/checkmate `checkState` so the
    /// audio classifier picks `.moveCheck`.
    func test_engine_check_is_classified_as_check_sound() async throws {
        // 1. f3 e5 2. g4 — black to move, Qh4# delivers mate
        let fen = "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2"
        guard let pos = Position(fen: fen) else {
            XCTFail("could not parse fen"); return
        }
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["d8h4"]
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )

        var capturedMove: Move?
        var capturedPre: Position?
        var capturedPost: Position?
        session.onMoveApplied = { move, pre, post, _ in
            capturedMove = move
            capturedPre = pre
            capturedPost = post
        }

        await session.bootstrap()

        let move = try XCTUnwrap(capturedMove, "engine reply never fired onMoveApplied")
        let pre = try XCTUnwrap(capturedPre)
        let post = try XCTUnwrap(capturedPost)
        let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: false)
        XCTAssertEqual(sfx, .moveCheck,
                       "engine-delivered check must produce the check sound, got \(sfx)")
    }
}
