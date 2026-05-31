import XCTest
import ChessKit
@testable import Chess_Openings

@MainActor
final class EnginePlayoutSessionDrawTests: XCTestCase {
    func test_engine_accepts_draw_when_eval_near_zero() async {
        let fake = FakeEngineService()
        fake.scriptedEvaluations = [.cp(20)]   // within ±50
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        await session.offerDraw()
        XCTAssertEqual(session.status, .gameOver(.drawAgreed))
    }

    func test_engine_accepts_draw_at_exact_threshold() async {
        let fake = FakeEngineService()
        fake.scriptedEvaluations = [.cp(50)]   // boundary
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        await session.offerDraw()
        XCTAssertEqual(session.status, .gameOver(.drawAgreed),
                       "engine should accept at exactly ±50 cp")
    }

    func test_engine_declines_when_clearly_winning() async {
        let fake = FakeEngineService()
        fake.scriptedEvaluations = [.cp(200)]  // 2 pawns up for engine
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        await session.offerDraw()
        XCTAssertEqual(session.status, .waitingForUser)
    }

    func test_engine_declines_when_clearly_losing() async {
        let fake = FakeEngineService()
        fake.scriptedEvaluations = [.cp(-200)] // engine 2 pawns down — still won't agree
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        await session.offerDraw()
        XCTAssertEqual(session.status, .waitingForUser)
    }

    func test_engine_declines_when_seeing_mate() async {
        let fake = FakeEngineService()
        fake.scriptedEvaluations = [.mate(in: 3)]
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        await session.offerDraw()
        XCTAssertEqual(session.status, .waitingForUser,
                       "an engine that sees mate should never agree to a draw")
    }

    func test_offer_draw_after_game_over_is_noop() async throws {
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
        let preCalls = fake.evaluateCalls
        await session.offerDraw()
        XCTAssertEqual(session.status, preStatus,
                       "draw offer must not change status after game over")
        XCTAssertEqual(fake.evaluateCalls, preCalls,
                       "draw offer must not query engine after game over")
    }

    func test_offer_draw_while_engine_thinking_is_noop() async {
        // construct a session where the user is mid-action — bootstrap into
        // black side so initial status is .engineThinking without calling
        // bootstrap.
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .black,
            level: .default,
            engine: fake
        )
        // status is .engineThinking before bootstrap fires
        XCTAssertEqual(session.status, .engineThinking)
        let preCalls = fake.evaluateCalls
        await session.offerDraw()
        XCTAssertEqual(session.status, .engineThinking,
                       "offer draw must be ignored while engine is thinking")
        XCTAssertEqual(fake.evaluateCalls, preCalls)
    }
}
