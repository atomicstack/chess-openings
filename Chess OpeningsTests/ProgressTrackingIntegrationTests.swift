import XCTest
import SwiftData
import ChessKit
@testable import Chess_Openings

/// Verifies the wiring between `DrillSession` and `ProgressService`.
///
/// The bug these tests cover: prior to fix, completing a drill line in
/// the app updated the session's in-memory `correctStreak` but never
/// persisted via `ProgressService`, so `line.mastery` was untouched
/// after the user navigated away. Mastery, streaks, and the mistake
/// log were effectively dead state.
@MainActor
final class ProgressTrackingIntegrationTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Opening.self,
            Line.self,
            LineProgress.self,
            UserSettings.self,
        ])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [cfg])
        return ModelContext(container)
    }

    private func makePersistedLine(in ctx: ModelContext, plies: [BookPly]) -> Line {
        let line = Line(name: "t", plies: plies)
        ctx.insert(line)
        return line
    }

    func test_clean_completion_persists_streak_and_attempt_counts() async throws {
        let ctx = try makeContext()
        let plies = [BookPly(san: "e4", uci: "e2e4"), BookPly(san: "e5", uci: "e7e5")]
        let line = makePersistedLine(in: ctx, plies: plies)

        let session = DrillSession(
            line: LineSnapshot(plies: plies),
            oracle: LineBookOracle(plies: plies),
            mode: .strict,
            masteryThreshold: 3
        )
        session.attachProgressTracking(line: line, threshold: 3, context: ctx)

        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)

        XCTAssertEqual(session.status, .lineComplete)
        XCTAssertEqual(line.mastery?.correctStreak, 1)
        XCTAssertEqual(line.mastery?.timesAttempted, 1)
        XCTAssertEqual(line.mastery?.timesCompleted, 1)
        XCTAssertEqual(line.mastery?.isLearned, false)
    }

    func test_clean_completions_reach_isLearned_at_threshold() async throws {
        let ctx = try makeContext()
        let plies = [BookPly(san: "e4", uci: "e2e4"), BookPly(san: "e5", uci: "e7e5")]
        let line = makePersistedLine(in: ctx, plies: plies)

        for _ in 0..<3 {
            let session = DrillSession(
                line: LineSnapshot(plies: plies),
                oracle: LineBookOracle(plies: plies),
                mode: .strict,
                masteryThreshold: 3,
                initialStreak: line.mastery?.correctStreak ?? 0
            )
            session.attachProgressTracking(line: line, threshold: 3, context: ctx)
            let e4 = try SanCodec.parse("e4", in: Position.standard)
            await session.submit(e4)
        }

        XCTAssertEqual(line.mastery?.correctStreak, 3)
        XCTAssertEqual(line.mastery?.isLearned, true)
        XCTAssertEqual(line.mastery?.timesAttempted, 3)
        XCTAssertEqual(line.mastery?.timesCompleted, 3)
    }

    func test_mistake_persists_to_mistakes_log() async throws {
        let ctx = try makeContext()
        let plies = [BookPly(san: "e4", uci: "e2e4"), BookPly(san: "e5", uci: "e7e5")]
        let line = makePersistedLine(in: ctx, plies: plies)

        let session = DrillSession(
            line: LineSnapshot(plies: plies),
            oracle: LineBookOracle(plies: plies),
            mode: .strict,
            masteryThreshold: 3
        )
        session.attachProgressTracking(line: line, threshold: 3, context: ctx)

        let d4 = try SanCodec.parse("d4", in: Position.standard)
        await session.submit(d4)

        let recorded = line.mastery?.mistakes ?? []
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.playedSan, "d4")
        XCTAssertEqual(recorded.first?.ply.san, "e4")
    }

    func test_completion_after_mistake_resets_streak_and_unlearns() async throws {
        let ctx = try makeContext()
        let plies = [BookPly(san: "e4", uci: "e2e4"), BookPly(san: "e5", uci: "e7e5")]
        let line = makePersistedLine(in: ctx, plies: plies)
        // pretend the user previously had it learned
        let initial = LineProgress()
        initial.correctStreak = 3
        initial.isLearned = true
        line.mastery = initial

        let session = DrillSession(
            line: LineSnapshot(plies: plies),
            oracle: LineBookOracle(plies: plies),
            mode: .showAndRetry,
            masteryThreshold: 3,
            initialStreak: 3
        )
        session.attachProgressTracking(line: line, threshold: 3, context: ctx)

        // play wrong, then correct, completing the line
        let d4 = try SanCodec.parse("d4", in: Position.standard)
        await session.submit(d4)
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)

        XCTAssertEqual(session.status, .lineComplete)
        XCTAssertEqual(line.mastery?.correctStreak, 0,
                       "a completion that included a mistake must zero the streak")
        XCTAssertEqual(line.mastery?.isLearned, false,
                       "a mistaken completion must clear the learned flag")
    }
}
