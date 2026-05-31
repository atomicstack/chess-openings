import XCTest
import ChessKit
@testable import Chess_Openings

/// Regression coverage for mid-drill restore — the user reported
/// "made a couple of moves in drill mode, force quit, nothing
/// restored" because we previously only persisted playout state.
final class DrillSessionRestoreTests: XCTestCase {

    @MainActor
    func test_restore_replays_drill_history_into_fresh_session() async throws {
        // play 1.e4 e5 into the original
        let line = makeLine(["e4", "e5", "Nf3", "Nc6"])
        let original = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await original.submit(e4)

        XCTAssertEqual(original.history.count, 2)
        let snapshot = zip(original.history, original.historyByUser)
            .map { StoredMove(move: $0, byUser: $1) }
        let originalFEN = original.position.fen

        // restore into a fresh session
        let restored = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        let reconstructed = snapshot.reconstruct(from: .standard)
        XCTAssertNotNil(reconstructed)
        restored.restore(history: reconstructed ?? [])

        XCTAssertEqual(restored.history.count, 2)
        XCTAssertEqual(restored.historyByUser, [true, false])
        XCTAssertEqual(restored.position.fen, originalFEN)
        XCTAssertEqual(restored.status, .waitingForUser)
    }

    @MainActor
    func test_restore_marks_complete_when_full_history_replayed() async throws {
        let line = makeLine(["e4", "e5"])
        let original = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await original.submit(e4)
        // line is 2 plies, e4 + scripted e5 -> complete
        XCTAssertEqual(original.status, .lineComplete)
        let snapshot = zip(original.history, original.historyByUser)
            .map { StoredMove(move: $0, byUser: $1) }

        let restored = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        let reconstructed = snapshot.reconstruct(from: .standard) ?? []
        restored.restore(history: reconstructed)
        XCTAssertEqual(restored.status, .lineComplete)
    }

    @MainActor
    func test_restore_suppresses_move_applied_callback() async throws {
        let line = makeLine(["e4", "e5", "Nf3", "Nc6"])
        let original = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await original.submit(e4)
        let snapshot = zip(original.history, original.historyByUser)
            .map { StoredMove(move: $0, byUser: $1) }
        let reconstructed = snapshot.reconstruct(from: .standard) ?? []

        let restored = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        var sfxFired = 0
        restored.onMoveApplied = { _, _, _, _ in sfxFired += 1 }
        restored.restore(history: reconstructed)
        XCTAssertEqual(sfxFired, 0, "restore must not retrigger move sfx")

        // callback must be re-attached after restore — verify by playing
        // the next move and expecting one user move + one scripted reply.
        let nf3 = try SanCodec.parse("Nf3", in: restored.position)
        await restored.submit(nf3)
        XCTAssertEqual(sfxFired, 2)
    }

    private func makeLine(_ sans: [String]) -> LineSnapshot {
        let plies = sans.map { BookPly(san: $0, uci: "0000") }
        return LineSnapshot(plies: plies)
    }
}
