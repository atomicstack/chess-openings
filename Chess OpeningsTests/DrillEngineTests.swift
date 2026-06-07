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
    func test_drillsession_undo_is_noop_before_any_user_move() async throws {
        // black-side setup: first ply is auto-played (byUser=false),
        // user hasn't moved yet. undo in this state used to empty the
        // history and silently flip which side the user was controlling.
        let line = makeTestLine(["e4", "e5", "Nf3", "Nc6"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3,
            userSide: .black
        )
        session.autoplayNextBookPly()
        XCTAssertEqual(session.history.count, 1)

        session.undo()

        XCTAssertEqual(session.history.count, 1,
                       "undo must not pop the autoplay move when the user hasn't played yet")
        XCTAssertEqual(session.preMovePositions.count, 1)
        XCTAssertEqual(session.status, .waitingForUser)
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
    func test_progressservice_updates_on_line_complete() {
        let line = Line(name: "t", plies: [BookPly(san: "e4", uci: "e2e4"), BookPly(san: "e5", uci: "e7e5")])
        line.mastery = LineProgress()
        let service = ProgressService()

        service.recordCompletion(line: line, madeMistake: false, threshold: 3)
        XCTAssertEqual(line.mastery?.correctStreak, 1)
        service.recordCompletion(line: line, madeMistake: false, threshold: 3)
        service.recordCompletion(line: line, madeMistake: false, threshold: 3)
        XCTAssertEqual(line.mastery?.isLearned, true)

        service.recordCompletion(line: line, madeMistake: true, threshold: 3)
        XCTAssertEqual(line.mastery?.correctStreak, 0)
        XCTAssertEqual(line.mastery?.isLearned, true,
                       "isLearned is sticky once reached — a later mistake only resets the streak")
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

    @MainActor
    func test_drillsession_preMovePositions_tracks_positions_for_san_trail() async throws {
        let line = makeTestLine(["e4", "e5", "Nf3", "Nc6"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        XCTAssertEqual(session.preMovePositions.count, 0)

        // first submit: user e4 + scripted reply e5 -> 2 moves, 2 pre-move positions
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)
        XCTAssertEqual(session.history.count, 2)
        XCTAssertEqual(session.preMovePositions.count, 2)
        // first pre-move is the initial position
        XCTAssertEqual(session.preMovePositions[0].fen, Position.standard.fen)
        // each entry must allow SAN formatting of the corresponding history move
        for i in 0..<session.history.count {
            let san = SanCodec.format(session.history[i], in: session.preMovePositions[i])
            XCTAssertFalse(san.isEmpty)
        }

        // second submit: Nf3 + Nc6 -> history 4, preMovePositions 4
        let nf3 = try SanCodec.parse("Nf3", in: session.position)
        await session.submit(nf3)
        XCTAssertEqual(session.history.count, 4)
        XCTAssertEqual(session.preMovePositions.count, 4)

        // undo steps back one full move: 4 -> 2
        session.undo()
        XCTAssertEqual(session.history.count, 2)
        XCTAssertEqual(session.preMovePositions.count, 2)

        // reset clears entirely
        session.reset()
        XCTAssertEqual(session.history.count, 0)
        XCTAssertEqual(session.preMovePositions.count, 0)
    }

    @MainActor
    func test_drillsession_onMoveApplied_fires_for_user_and_reply() async throws {
        let line = makeTestLine(["e4", "e5", "Nf3"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        var events: [(String, Bool)] = []
        session.onMoveApplied = { move, pre, _, byUser in
            events.append((SanCodec.format(move, in: pre), byUser))
        }
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.0, "e4")
        XCTAssertEqual(events.first?.1, true)
        XCTAssertEqual(events.last?.0, "e5")
        XCTAssertEqual(events.last?.1, false)
    }

    @MainActor
    func test_drillsession_onMoveApplied_fires_for_autoplay() async throws {
        let line = makeTestLine(["e4", "e5"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        var events: [(String, Bool)] = []
        session.onMoveApplied = { move, pre, _, byUser in
            events.append((SanCodec.format(move, in: pre), byUser))
        }
        session.autoplayNextBookPly()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.0, "e4")
        XCTAssertEqual(events.first?.1, false)
    }

    @MainActor
    func test_drillsession_accepts_user_capture_constructed_via_board() async throws {
        // repro: user plays a capture via Board.move(pieceAt:to:), which
        // returns a Move with .result = .capture(piece). the oracle's move
        // comes from SANParser.parse and may differ in metadata
        // (disambiguation, check state, piece.square), so full Move equality
        // rejects the capture even though it is the correct book move.
        let line = makeTestLine(["e4", "d5", "exd5"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )

        var board = Board(position: .standard)
        guard let e4 = board.move(pieceAt: Square("e2"), to: Square("e4")) else {
            XCTFail("e4 should be legal"); return
        }
        await session.submit(e4)
        XCTAssertEqual(session.history.count, 2)

        var playerBoard = Board(position: session.position)
        guard let exd5 = playerBoard.move(pieceAt: Square("e4"), to: Square("d5")) else {
            XCTFail("exd5 should be legal"); return
        }
        if case .capture = exd5.result {} else { XCTFail("exd5 must be a capture") }

        await session.submit(exd5)
        XCTAssertEqual(session.history.count, 3, "user capture should be accepted by the session")
        XCTAssertEqual(session.status, .lineComplete)
    }

    // MARK: - DrillProgress

    func test_drillprogress_white_side_counts_even_indexed_plies() {
        // line: e4 e5 Nf3 Nc6 Bc4  -> total plies 5, user moves 3
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 0, totalPlies: 5, side: .white).played, 0)
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 1, totalPlies: 5, side: .white).played, 1)
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 2, totalPlies: 5, side: .white).played, 1)
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 3, totalPlies: 5, side: .white).played, 2)
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 5, totalPlies: 5, side: .white).played, 3)
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 0, totalPlies: 5, side: .white).total, 3)
    }

    func test_drillprogress_black_side_counts_odd_indexed_plies() {
        // line: e4 e5 Nf3 Nc6 -> total plies 4, user (black) moves 2
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 0, totalPlies: 4, side: .black).played, 0)
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 1, totalPlies: 4, side: .black).played, 0)
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 2, totalPlies: 4, side: .black).played, 1)
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 3, totalPlies: 4, side: .black).played, 1)
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 4, totalPlies: 4, side: .black).played, 2)
        XCTAssertEqual(DrillProgress.userMoves(historyCount: 0, totalPlies: 4, side: .black).total, 2)
    }

    @MainActor
    func test_drillsession_fires_onLineComplete_when_user_finishes_line() async throws {
        let line = makeTestLine(["e4", "e5"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        var fired = 0
        session.onLineComplete = { fired += 1 }

        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)

        XCTAssertEqual(session.status, .lineComplete)
        XCTAssertEqual(fired, 1)
    }

    @MainActor
    func test_drillsession_fires_onLineComplete_on_terminal_autoplay() async throws {
        // single-ply line finishes on the very first autoplay call.
        let line = makeTestLine(["e4"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        var fired = 0
        session.onLineComplete = { fired += 1 }

        session.autoplayNextBookPly()

        XCTAssertEqual(session.status, .lineComplete)
        XCTAssertEqual(fired, 1)
    }

    @MainActor
    func test_drillsession_fires_onIncorrectMove_for_offbook_strict() async throws {
        let line = makeTestLine(["e4", "e5"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        var fired = 0
        session.onIncorrectMove = { _, _ in fired += 1 }

        let d4 = try SanCodec.parse("d4", in: Position.standard)
        await session.submit(d4)

        XCTAssertEqual(fired, 1)
    }

    @MainActor
    func test_drillsession_fires_onIncorrectMove_for_offbook_showAndRetry() async throws {
        let line = makeTestLine(["e4", "e5"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .showAndRetry,
            masteryThreshold: 3
        )
        var fired = 0
        session.onIncorrectMove = { _, _ in fired += 1 }

        let d4 = try SanCodec.parse("d4", in: Position.standard)
        await session.submit(d4)

        XCTAssertEqual(fired, 1)
    }

    @MainActor
    func test_drillsession_averageSecondsPerPly_is_nil_until_line_complete() async throws {
        let line = makeTestLine(["e4", "e5", "Nf3", "Nc6"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        XCTAssertNil(session.averageSecondsPerPly)

        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)
        // line not yet complete — still nil
        XCTAssertNil(session.averageSecondsPerPly)
    }

    @MainActor
    func test_drillsession_averageSecondsPerPly_set_after_completion() async throws {
        let line = makeTestLine(["e4", "e5"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)

        guard let avg = session.averageSecondsPerPly else {
            return XCTFail("averageSecondsPerPly should be non-nil after completion")
        }
        // 2-ply line, instant submit — avg comfortably under 1s/ply.
        XCTAssertLessThan(avg, 1.0)
        XCTAssertGreaterThanOrEqual(avg, 0.0)
    }

    @MainActor
    func test_drillsession_timing_excludes_scripted_reply_delay() async throws {
        // simulate a slow UI reply delay (200ms). that 200ms is spent by
        // the computer between the user's move and the reply being applied,
        // so it must NOT be counted against the user's thinking time.
        let line = makeTestLine(["e4", "e5"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        session.scriptedReplyDelayMs = 200

        let e4 = try SanCodec.parse("e4", in: Position.standard)
        let wallStart = Date()
        await session.submit(e4)
        let wallElapsed = Date().timeIntervalSince(wallStart)

        // sanity: submit actually took at least the reply delay.
        XCTAssertGreaterThanOrEqual(wallElapsed, 0.2, "submit should have slept for the reply delay")
        // user thinking time must be strictly less than wall-clock elapsed,
        // and specifically less than the reply delay itself (since the
        // submit was otherwise instant).
        XCTAssertLessThan(session.userThinkingTime, 0.2)
    }

    @MainActor
    func test_drillsession_reset_clears_timing() async throws {
        let line = makeTestLine(["e4", "e5"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)
        XCTAssertNotNil(session.averageSecondsPerPly)

        session.reset()

        XCTAssertEqual(session.userThinkingTime, 0)
        XCTAssertNil(session.averageSecondsPerPly)
    }

    /// Show-line attribution: when the playback feature drives the
    /// final ply, `completedViaShowLine` flips on; a normal user-driven
    /// completion leaves it false. The drill view keys the perfect /
    /// speedy banners off this so the user doesn't get medals for
    /// watching the line play itself.
    @MainActor
    func test_completedViaShowLine_marks_only_playback_finishes() async throws {
        let line = makeTestLine(["e4", "e5"])

        // path 1: show-line autoplays both plies
        let watched = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        watched.autoplayNextBookPly(viaShowLine: true)
        watched.autoplayNextBookPly(viaShowLine: true)
        XCTAssertEqual(watched.status, .lineComplete)
        XCTAssertTrue(watched.completedViaShowLine,
                      "show-line drove the completion — flag must be set")

        // path 2: user finishes manually
        let played = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3
        )
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await played.submit(e4)
        XCTAssertEqual(played.status, .lineComplete)
        XCTAssertFalse(played.completedViaShowLine,
                       "user-driven completion must not set the flag")
    }

    /// Hard invariant: at the end of `undo()`, `position.sideToMove`
    /// must equal `userSide`. Anything else means the user effectively
    /// controls the opponent's pieces, because `BoardView`'s drag
    /// predicate gates by `position.sideToMove`. This bug has shipped
    /// FOUR times — see CLAUDE.md "user controls the wrong side" note.
    @MainActor
    func test_undo_always_leaves_user_to_move_after_show_line() async throws {
        // white user: e4, reply e5, show-line plays Nf3 → side=black
        let line = makeTestLine(["e4", "e5", "Nf3", "Nc6"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3,
            userSide: .white
        )
        let e4 = try SanCodec.parse("e4", in: Position.standard)
        await session.submit(e4)
        XCTAssertEqual(session.history.count, 2)
        XCTAssertEqual(session.position.sideToMove, .white)

        session.autoplayNextBookPly() // Nf3 — now black to move
        XCTAssertEqual(session.history.count, 3)
        XCTAssertEqual(session.position.sideToMove, .black,
                       "sanity: show-line left us on the opponent's clock")

        session.undo()
        XCTAssertEqual(session.position.sideToMove, .white,
                       "undo must restore the user to the clock — opponent-to-move is the side-swap bug")
        XCTAssertEqual(session.history.count, 2,
                       "pop the single show-line ply to land on the user's turn")
    }

    /// Undo must work even when the user hasn't played anything yet —
    /// e.g. they hit "show line" first thing to preview the line.
    /// Original `lastIndex(of: true)` guard short-circuited and made
    /// undo a no-op in that state.
    @MainActor
    func test_undo_works_with_only_show_line_plies() async throws {
        let line = makeTestLine(["e4", "e5", "Nf3"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3,
            userSide: .white
        )
        session.autoplayNextBookPly() // e4
        session.autoplayNextBookPly() // e5
        XCTAssertEqual(session.history.count, 2)

        session.undo()
        XCTAssertEqual(session.history.count, 0,
                       "undo must pop even when the user hasn't played anything personally")
        XCTAssertEqual(session.position.sideToMove, .white)
    }

    /// Black-side scaffold must be preserved across undo. The user is
    /// playing black: the initial white opener is autoplayed as a
    /// scaffold. Undo from "scaffold + show-line plies" must land at
    /// "scaffold only" and stop there — never reveal a white-to-move
    /// state to the black user.
    @MainActor
    func test_undo_preserves_black_side_scaffold() async throws {
        let line = makeTestLine(["e4", "e5", "Nf3", "Nc6"])
        let session = DrillSession(
            line: line,
            oracle: LineBookOracle(plies: line.plies),
            mode: .strict,
            masteryThreshold: 3,
            userSide: .black
        )
        // scaffold: white plays e4 for the black user
        session.autoplayNextBookPly()
        XCTAssertEqual(session.position.sideToMove, .black)

        // show-line continues: e5 then Nf3
        session.autoplayNextBookPly() // e5
        session.autoplayNextBookPly() // Nf3
        XCTAssertEqual(session.history.count, 3)
        XCTAssertEqual(session.position.sideToMove, .black)

        // undo pops back to the most-recent black-to-move state, which
        // is "just after the scaffold ply" — popping both e5 and Nf3.
        session.undo()
        XCTAssertEqual(session.history.count, 1,
                       "should land at the scaffold ply (most recent black-to-move state)")
        XCTAssertEqual(session.position.sideToMove, .black)

        // another undo: no earlier black-to-move state exists — the
        // scaffold's preMovePosition is the standard position (white
        // to move), so the algorithm correctly no-ops here.
        session.undo()
        XCTAssertEqual(session.history.count, 1,
                       "undo must never pop past the black-side scaffold")
        XCTAssertEqual(session.position.sideToMove, .black)
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
