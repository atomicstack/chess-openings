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

    @MainActor
    func test_drillsession_showandretry_wrong_move_transitions_to_mistake() async throws {
        let line = makeTestLine(["e4", "e5", "Bc4"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .showAndRetry,
            masteryThreshold: 3
        )
        let d4 = try SanCodec.parse("d4", in: Position.standard)
        await session.submit(d4)

        switch session.status {
        case .mistake(let book, let played):
            XCTAssertEqual(book.san, "e4")
            XCTAssertEqual(played.end.notation, "d4")
        default:
            XCTFail("expected .mistake, got \(session.status)")
        }
        XCTAssertEqual(session.correctStreak, 0)
    }

    @MainActor
    func test_drillsession_showandretry_recovers_on_book_move() async throws {
        let line = makeTestLine(["e4", "e5", "Nf3"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .showAndRetry,
            masteryThreshold: 3
        )
        let d4 = try SanCodec.parse("d4", in: Position.standard)
        await session.submit(d4)
        XCTAssertTrue(isMistake(session.status))

        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)
        XCTAssertEqual(session.status, .waitingForUser)
        XCTAssertEqual(session.history.count, 2)  // recovered + reply
    }

    private func isMistake(_ s: DrillStatus) -> Bool {
        if case .mistake = s { return true }; return false
    }

    @MainActor
    func test_drillsession_undo_steps_back_one_full_move() async throws {
        let line = makeTestLine(["e4", "e5", "Nf3", "Nc6"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)
        XCTAssertEqual(session.history.count, 2)

        session.undo()
        XCTAssertEqual(session.history.count, 0)
        XCTAssertEqual(session.status, .waitingForUser)
    }

    @MainActor
    func test_drillsession_reset_returns_to_start() async throws {
        let line = makeTestLine(["e4", "e5"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)

        session.reset()
        XCTAssertEqual(session.history.count, 0)
        XCTAssertEqual(session.position.fen, Position.standard.fen)
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
