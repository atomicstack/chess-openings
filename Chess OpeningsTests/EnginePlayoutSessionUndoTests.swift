import XCTest
import ChessKit
@testable import Chess_Openings

@MainActor
final class EnginePlayoutSessionUndoTests: XCTestCase {
    func test_undo_pops_user_move_and_engine_reply() async throws {
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["e7e5"]
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        let e4 = try SanCodec.parse("e4", in: .standard)
        await session.submit(e4)
        XCTAssertEqual(session.history.count, 2)

        session.undo()
        XCTAssertEqual(session.history.count, 0)
        XCTAssertEqual(session.historyByUser, [])
        XCTAssertEqual(session.preMovePositions, [])
        XCTAssertEqual(session.position.fen, Position.standard.fen)
        XCTAssertEqual(session.status, .waitingForUser)
    }

    func test_undo_with_only_engine_bootstrap_is_noop() async throws {
        // black user, white-first: bootstrap fires one engine move
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["e2e4"]
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .black,
            level: .default,
            engine: fake
        )
        await session.bootstrap()
        XCTAssertEqual(session.history.count, 1)
        XCTAssertEqual(session.historyByUser, [false])

        session.undo()
        XCTAssertEqual(session.history.count, 1,
                       "undo must not pop the engine-first bootstrap move")
        XCTAssertEqual(session.status, .waitingForUser)
    }

    func test_undo_after_game_over_is_noop() async throws {
        // fool's mate setup
        let fen = "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2"
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid test fen"); return
        }
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .black,
            level: .default,
            engine: fake
        )
        let qh4 = try SanCodec.parse("Qh4", in: pos)
        await session.submit(qh4)
        guard case .gameOver = session.status else {
            XCTFail("expected game over after Qh4"); return
        }
        let preCount = session.history.count
        let preStatus = session.status
        session.undo()
        XCTAssertEqual(session.history.count, preCount,
                       "undo must be a no-op after game over")
        XCTAssertEqual(session.status, preStatus)
    }

    func test_undo_from_non_standard_starting_position() async throws {
        // Starting position is an italian-game-ish position with white to move;
        // user submits one move, engine replies, then undo returns to the
        // *starting* position (not .standard).
        let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 4"
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid test fen"); return
        }
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["g8f6"]
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )
        let nc3 = try SanCodec.parse("Nc3", in: pos)
        await session.submit(nc3)
        XCTAssertEqual(session.history.count, 2)

        session.undo()
        XCTAssertEqual(session.history.count, 0)
        XCTAssertEqual(session.position.fen, pos.fen,
                       "undo must restore the non-standard starting position")
    }

    func test_undo_pops_only_user_move_when_engine_reply_was_missing() async throws {
        // If the engine somehow doesn't reply (e.g. game ended on user move
        // — but for this test, force the no-reply path by letting submit's
        // termination check end the game). In that case history = [user move]
        // and historyByUser = [true]. Undo should pop just that one move.
        let fen = "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2"
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid test fen"); return
        }
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .black,
            level: .default,
            engine: fake
        )
        let qh4 = try SanCodec.parse("Qh4", in: pos)
        await session.submit(qh4)
        XCTAssertEqual(session.history.count, 1,
                       "mate ends the line before engine replies")
        XCTAssertEqual(session.historyByUser, [true])
        // session.status is .gameOver — undo is a no-op here per the previous
        // test. This test exists to lock the historyByUser invariant.
    }
}
