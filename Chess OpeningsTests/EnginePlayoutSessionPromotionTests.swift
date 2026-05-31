import XCTest
import ChessKit
@testable import Chess_Openings

/// Regression coverage for the chesskit two-step promotion mechanic.
///
/// `board.move(pieceAt:to:)` on a pawn-to-final-rank does NOT commit a
/// promotion — it returns the pending `Move?` and leaves the board in
/// `.promotion(_)` state. The session's `apply()` helper must follow
/// up with `board.completePromotion(of:to:)` when the incoming `Move`
/// has `promotedPiece` set, otherwise:
///
///  - the user's piece never actually becomes a queen,
///  - the board sits in `.promotion` state so `submit()` early-returns
///    without queueing the engine reply, and
///  - chesskit's position toggles side-to-move regardless, so the user
///    appears to "lose control" of their pieces mid-promotion.
///
/// This bug shipped twice (once in `DrillSession.apply`, once in
/// `EnginePlayoutSession.apply`). These tests pin the contract.
@MainActor
final class EnginePlayoutSessionPromotionTests: XCTestCase {
    func test_user_promotion_to_queen_commits_and_lets_engine_reply() async throws {
        // white pawn on e7, kings safely apart; user promotes to queen
        // which gives check; black king must escape to h7.
        let fen = "7k/4P3/8/8/8/8/8/4K3 w - - 0 1"
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid test fen"); return
        }

        // Construct the user's promotion-finalised Move the same way
        // BoardView does: a local board to materialise the pending
        // move, then completePromotion to attach the queen choice.
        var tempBoard = Board(position: pos)
        let from = Square("e7")
        let to = Square("e8")
        guard let pending = tempBoard.move(pieceAt: from, to: to) else {
            XCTFail("pawn-to-8th must be a legal move from the test fen"); return
        }
        let promotionMove = tempBoard.completePromotion(of: pending, to: .queen)

        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["h8h7"]
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )

        await session.submit(promotionMove)

        XCTAssertEqual(session.history.count, 2,
                       "user promotion + engine reply should both land in history")
        XCTAssertEqual(session.historyByUser, [true, false])
        XCTAssertEqual(session.position.piece(at: Square("e8") as Square)?.kind, .queen,
                       "promotion must replace the pawn with a queen")
        XCTAssertEqual(session.position.piece(at: Square("e8") as Square)?.color, .white,
                       "the promoted queen must be the user's colour")
        XCTAssertEqual(session.status, .waitingForUser,
                       "engine should have replied; control returns to the user")
        XCTAssertEqual(fake.bestMoveCalls, 1,
                       "engine reply must have fired (board not stuck in .promotion)")
    }

    func test_user_promotion_then_undo_restores_pawn() async throws {
        let fen = "7k/4P3/8/8/8/8/8/4K3 w - - 0 1"
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid test fen"); return
        }
        var tempBoard = Board(position: pos)
        let from = Square("e7")
        let to = Square("e8")
        guard let pending = tempBoard.move(pieceAt: from, to: to) else {
            XCTFail("legal"); return
        }
        let promotionMove = tempBoard.completePromotion(of: pending, to: .queen)

        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["h8h7"]
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )
        await session.submit(promotionMove)
        XCTAssertEqual(session.position.piece(at: Square("e8") as Square)?.kind, .queen)

        session.undo()

        // Rebuild from history must also honor promotion semantics.
        XCTAssertEqual(session.history.count, 0)
        XCTAssertEqual(session.position.fen, pos.fen,
                       "undo must restore the pre-promotion position exactly")
        XCTAssertEqual(session.position.piece(at: Square("e7") as Square)?.kind, .pawn,
                       "the white pawn should be back on e7 after undo")
    }
}
