import XCTest
import ChessKit
@testable import Chess_Openings

@MainActor
final class EnginePlayoutSessionInitTests: XCTestCase {
    func test_user_to_move_starts_waiting_for_user() async {
        // startpos: white to move
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        XCTAssertEqual(session.status, .waitingForUser)
        XCTAssertEqual(fake.bestMoveCalls, 0)
    }

    func test_engine_to_move_status_is_engine_thinking_before_bootstrap() async {
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .black,
            level: .default,
            engine: fake
        )
        XCTAssertEqual(session.status, .engineThinking)
        XCTAssertEqual(fake.bestMoveCalls, 0,
                       "engine should not be queried until bootstrap()")
    }

    func test_engine_to_move_bootstrap_plays_and_hands_off() async {
        // user (black) — engine plays white's e2e4 first
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["e2e4"]
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .black,
            level: .default,
            engine: fake
        )
        await session.bootstrap()
        XCTAssertEqual(fake.bestMoveCalls, 1)
        XCTAssertEqual(session.history.count, 1)
        XCTAssertEqual(session.historyByUser, [false],
                       "the bootstrap move is the engine's, not the user's")
        XCTAssertEqual(session.status, .waitingForUser)
        XCTAssertEqual(fake.lastBestMoveSkill, 10,
                       "uses the level's skill, not 20")
    }

    func test_bootstrap_is_idempotent_when_user_to_move() async {
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        await session.bootstrap()
        XCTAssertEqual(fake.bestMoveCalls, 0,
                       "no engine call when user is on move at start")
        XCTAssertEqual(session.status, .waitingForUser)
    }
}
