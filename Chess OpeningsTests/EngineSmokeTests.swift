import XCTest
import ChessKit
@testable import Chess_Openings

/// Boots a real stockfish via chesskit-engine and asserts the engine
/// returns a bestmove from the starting position. Excluded from the
/// default run via `XCTSkipUnless` — enable by setting the env var
/// `RUN_ENGINE_INTEGRATION=1` in the test scheme or shell:
///
///     RUN_ENGINE_INTEGRATION=1 make test T="Chess OpeningsTests/EngineSmokeTests"
@MainActor
final class EngineSmokeTests: XCTestCase {
    func test_stockfish_returns_bestmove_from_startpos() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_ENGINE_INTEGRATION"] == "1",
            "set RUN_ENGINE_INTEGRATION=1 to run the stockfish smoke test"
        )
        let service = EngineService()
        let move = await service.bestMove(
            at: .standard,
            skill: 20,
            budget: .movetimeMs(300)
        )
        let m = try XCTUnwrap(move, "engine returned no bestmove")
        XCTAssertGreaterThanOrEqual(m.uci.count, 4,
                                    "uci move must be 4 chars (or 5 with promo)")
        await service.shutdown()
    }
}
