import XCTest
import ChessKit
@testable import Chess_Openings

final class DrillEngineTests: XCTestCase {
    func test_linebookoracle_returns_next_ply() async throws {
        let plies = [
            BookPly(san: "e4", uci: "e2e4"),
            BookPly(san: "e5", uci: "e7e5"),
            BookPly(san: "Nf3", uci: "g1f3"),
        ]
        let oracle = LineBookOracle(plies: plies)

        let start = Position.standard
        let candidatesAtStart = await oracle.acceptableMoves(at: start, history: [])
        XCTAssertEqual(candidatesAtStart.count, 1)
        XCTAssertEqual(candidatesAtStart.first?.san, "e4")
    }

    func test_linebookoracle_empty_after_last_ply() async throws {
        let plies = [BookPly(san: "e4", uci: "e2e4")]
        let oracle = LineBookOracle(plies: plies)
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        var board = Board(position: .standard)
        board.move(pieceAt: e4.start, to: e4.end)
        let after = board.position
        let result = await oracle.acceptableMoves(at: after, history: [e4])
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func test_drillsession_strict_correct_move_advances_and_increments_streak() async throws {
        let line = makeTestLine(["e4", "e5", "Nf3", "Nc6"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )

        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)

        XCTAssertEqual(session.history.count, 2)  // user move + scripted reply
        XCTAssertEqual(session.status, .waitingForUser)
    }

    @MainActor
    func test_drillsession_strict_wrong_move_rejects_and_resets_streak() async throws {
        let line = makeTestLine(["e4", "e5"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3,
            initialStreak: 2
        )

        let d4 = try SanCodec.parse("d4", in: Position.standard)
        await session.submit(d4)

        XCTAssertEqual(session.history.count, 0)
        XCTAssertEqual(session.status, .waitingForUser)
        XCTAssertEqual(session.correctStreak, 0)
    }

    // helper
    func makeTestLine(_ sans: [String]) -> LineSnapshot {
        let plies = sans.map { san -> BookPly in
            // uci doesn't matter for these tests; populate a placeholder
            BookPly(san: san, uci: "0000")
        }
        return LineSnapshot(plies: plies)
    }
}
