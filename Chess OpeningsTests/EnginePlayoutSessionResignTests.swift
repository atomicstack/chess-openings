import XCTest
import ChessKit
@testable import Chess_Openings

@MainActor
final class EnginePlayoutSessionResignTests: XCTestCase {
    func test_user_resign_ends_game() async {
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        session.resign()
        XCTAssertEqual(session.status, .gameOver(.userResigned))
    }

    func test_user_resign_after_game_over_is_noop() async throws {
        let fen = "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2"
        guard let pos = Position(fen: fen) else { XCTFail(); return }
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .black,
            level: .default,
            engine: fake
        )
        let qh4 = try SanCodec.parse("Qh4", in: pos)
        await session.submit(qh4)
        let preStatus = session.status
        session.resign()
        XCTAssertEqual(session.status, preStatus)
    }

    func test_engine_resigns_when_window_fills_with_low_evals() async throws {
        // Start from a position where white has many quiet legal pawn moves
        // and the engine has at least one legal reply each turn.
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        guard let pos = Position(fen: fen) else { XCTFail(); return }
        let fake = FakeEngineService()
        // shrink the window for test speed; default is 6 in production
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )
        session.resignationThresholdCp = 300
        session.resignationWindowSize = 2
        fake.scriptedBestMoves = ["e7e5", "g8f6"]
        fake.scriptedEvaluations = [.cp(-400), .cp(-400)]

        let e4 = try SanCodec.parse("e4", in: session.position)
        await session.submit(e4)
        XCTAssertEqual(session.status, .waitingForUser)
        let d4 = try SanCodec.parse("d4", in: session.position)
        await session.submit(d4)
        XCTAssertEqual(session.status,
                       .gameOver(.engineResigned(accepted: nil)))
    }

    func test_engine_resign_then_user_declines_clears_window() async throws {
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        guard let pos = Position(fen: fen) else { XCTFail(); return }
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )
        session.resignationThresholdCp = 300
        session.resignationWindowSize = 2
        fake.scriptedBestMoves = ["e7e5", "g8f6"]
        fake.scriptedEvaluations = [.cp(-400), .cp(-400)]

        let e4 = try SanCodec.parse("e4", in: session.position)
        await session.submit(e4)
        let d4 = try SanCodec.parse("d4", in: session.position)
        await session.submit(d4)
        guard case .gameOver(.engineResigned(accepted: nil)) = session.status else {
            XCTFail("expected engineResigned modal"); return
        }
        session.declineEngineResignation()
        XCTAssertEqual(session.status, .waitingForUser)
    }

    func test_engine_resign_user_accepts_marks_accepted() async throws {
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        guard let pos = Position(fen: fen) else { XCTFail(); return }
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )
        session.resignationThresholdCp = 300
        session.resignationWindowSize = 2
        fake.scriptedBestMoves = ["e7e5", "g8f6"]
        fake.scriptedEvaluations = [.cp(-400), .cp(-400)]

        let e4 = try SanCodec.parse("e4", in: session.position)
        await session.submit(e4)
        let d4 = try SanCodec.parse("d4", in: session.position)
        await session.submit(d4)
        session.acceptEngineResignation()
        XCTAssertEqual(session.status,
                       .gameOver(.engineResigned(accepted: true)))
    }

    func test_window_resets_when_engine_eval_above_threshold() async throws {
        // a single -400 followed by a +400 should NOT trigger resignation;
        // the second eval clears the window.
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        guard let pos = Position(fen: fen) else { XCTFail(); return }
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )
        session.resignationThresholdCp = 300
        session.resignationWindowSize = 2
        fake.scriptedBestMoves = ["e7e5", "g8f6"]
        fake.scriptedEvaluations = [.cp(-400), .cp(50)]

        let e4 = try SanCodec.parse("e4", in: session.position)
        await session.submit(e4)
        let d4 = try SanCodec.parse("d4", in: session.position)
        await session.submit(d4)
        XCTAssertEqual(session.status, .waitingForUser,
                       "+50 cp clears the window — no resignation")
    }
}
