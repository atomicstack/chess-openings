import XCTest
import ChessKit
@testable import Chess_Openings

/// Regression: user reported "i resumed a danish gambit line ... when
/// i get to playthrough mode ... the computer opponent never makes a
/// move". Restored sessions must continue accepting user moves and
/// dispatching engine replies the same as freshly-built ones.
@MainActor
final class EnginePlayoutSessionRestoreSubmitTests: XCTestCase {

    /// Danish gambit drill end position — after 1.e4 e5 2.d4 exd4 3.c3
    /// dxc3 — white to move. Playout starts at this FEN and the user
    /// is white.
    private let danishEnd = "rnbqkbnr/pppp1ppp/8/8/4P3/2p5/PP3PPP/RNBQKBNR w KQkq - 0 4"

    func test_restored_session_with_empty_history_replies_to_user_move() async throws {
        guard let pos = Position(fen: danishEnd) else {
            XCTFail("invalid test fen"); return
        }
        let fake = FakeEngineService()
        // engine reply for black after Nxc3 — Bb4 (f8 → b4)
        fake.scriptedBestMoves = ["f8b4"]
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )
        // mirror DrillView.restorePlayout: empty history (user hadn't
        // moved yet when the snapshot was taken)
        session.restore(history: [])
        XCTAssertEqual(session.status, .waitingForUser)

        // user recaptures with the b1 knight — natural Danish reply
        let move = try SanCodec.parse("Nxc3", in: pos)
        await session.submit(move)

        XCTAssertEqual(session.history.count, 2,
                       "engine should have replied after user move")
        XCTAssertEqual(session.historyByUser, [true, false])
        XCTAssertEqual(fake.bestMoveCalls, 1,
                       "submit should have issued exactly one bestMove call")
        XCTAssertEqual(session.status, .waitingForUser)
    }

    func test_restored_session_with_history_still_replies_to_user_move() async throws {
        guard let pos = Position(fen: danishEnd) else {
            XCTFail("invalid test fen"); return
        }
        let fake = FakeEngineService()
        // first engine reply after the priming user move (during the
        // build-up history): irrelevant, replayed silently. Then the
        // real bestMove call we care about — after the SECOND user
        // move in the resumed session.
        fake.scriptedBestMoves = ["b4c3"]
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )
        // resemble a snapshot that captured the user's first playout
        // move + the engine's reply (already on the board pre-restart)
        let nxc3 = try SanCodec.parse("Nxc3", in: pos)
        var board = Board(position: pos)
        _ = board.move(pieceAt: nxc3.start, to: nxc3.end)
        let posAfterNxc3 = board.position
        // black plays a light-square bishop move
        let bb4 = try SanCodec.parse("Bb4", in: posAfterNxc3)

        session.restore(history: [
            (move: nxc3, byUser: true),
            (move: bb4, byUser: false),
        ])
        XCTAssertEqual(session.history.count, 2)
        XCTAssertEqual(session.status, .waitingForUser,
                       "after 2 plies it's white (the user) to move again")
        // restore must not have consumed any engine scripts
        XCTAssertEqual(fake.bestMoveCalls, 0)

        // user makes another move — engine should reply.
        let nextPos = session.position
        let userMove = try SanCodec.parse("a3", in: nextPos)
        await session.submit(userMove)

        XCTAssertEqual(session.history.count, 4)
        XCTAssertEqual(session.historyByUser, [true, false, true, false])
        XCTAssertEqual(fake.bestMoveCalls, 1)
        XCTAssertEqual(session.status, .waitingForUser)
    }
}
