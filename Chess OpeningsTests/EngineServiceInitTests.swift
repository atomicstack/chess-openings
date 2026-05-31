import XCTest
import ChessKit
@testable import Chess_Openings

/// Regression coverage for the user-reported bug: "i resumed a danish
/// gambit line ... the hint and best move buttons don't work any more,
/// and the computer opponent never makes a move." Root cause was
/// `EngineService.runInitialSetup` racing chesskit-engine 0.7's
/// detached AsyncStream-continuation setup, so the implicit readyok
/// emitted by the library's setup loop arrived BEFORE our consume()
/// had a stream to read from. The `for await r in stream` then
/// blocked forever waiting for a readyok that had already passed. All
/// subsequent engine calls (hint, post-move analysis, engine reply)
/// hung in the serialised work chain.
///
/// These tests exercise the real stockfish boot path — no env-gating —
/// and time out if the engine hangs at startup. A pass means the
/// readiness handshake we drive ourselves completes within a few
/// seconds of fresh init.
@MainActor
final class EngineServiceInitTests: XCTestCase {

    func test_bestmove_returns_within_timeout_on_fresh_init() async throws {
        let service = EngineService()
        defer { Task { await service.shutdown() } }

        let decision = try await withTimeout(seconds: 8) {
            await service.bestMove(
                at: .standard,
                skill: 20,
                budget: .movetimeMs(200)
            )
        }
        let d = try XCTUnwrap(decision, "engine returned no bestmove")
        XCTAssertGreaterThanOrEqual(d.move.uci.count, 4)
    }

    /// Two back-to-back queries (mirrors the resume scenario where the
    /// precompute and the post-move analyser fire in close succession).
    func test_back_to_back_queries_both_complete() async throws {
        let service = EngineService()
        defer { Task { await service.shutdown() } }

        let first = try await withTimeout(seconds: 8) {
            await service.bestMove(
                at: .standard, skill: 20, budget: .movetimeMs(150)
            )
        }
        XCTAssertNotNil(first)

        let second = try await withTimeout(seconds: 4) {
            await service.evaluate(at: .standard, budget: .movetimeMs(150))
        }
        // evaluate returns .cp(0) as a fallback; the important part is
        // that it actually returned within the timeout
        _ = second
    }

    // MARK: - helpers

    private struct TestTimeoutError: Error {}

    /// Runs `work` and throws `TestTimeoutError` if it doesn't return
    /// within the deadline. Implemented with Task race rather than
    /// `XCTWaiter` so async returns can be awaited directly.
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ work: @Sendable @escaping () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await work()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TestTimeoutError()
            }
            guard let first = try await group.next() else {
                throw TestTimeoutError()
            }
            group.cancelAll()
            return first
        }
    }
}
