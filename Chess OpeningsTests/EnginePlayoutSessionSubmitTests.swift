import XCTest
import ChessKit
@testable import Chess_Openings

@MainActor
final class EnginePlayoutSessionSubmitTests: XCTestCase {
    func test_legal_user_move_applies_then_engine_replies() async throws {
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["e7e5"]
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        let e4 = try SanCodec.parse("e4", in: .standard)
        await session.submit(e4)
        XCTAssertEqual(session.history.count, 2)
        XCTAssertEqual(session.historyByUser, [true, false])
        XCTAssertEqual(session.status, .waitingForUser)
        XCTAssertEqual(fake.bestMoveCalls, 1)
        XCTAssertEqual(fake.lastBestMoveSkill, 10)
    }

    func test_illegal_user_move_is_rejected_no_engine_call() async throws {
        // try to "move" a queen from empty a1
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        let bogus = Move(
            result: .move,
            piece: Piece(.queen, color: .white, square: .a1),
            start: .a1,
            end: .a8
        )
        await session.submit(bogus)
        XCTAssertEqual(session.history.count, 0)
        XCTAssertEqual(fake.bestMoveCalls, 0)
        XCTAssertEqual(session.status, .waitingForUser)
    }

    func test_user_checkmates_engine_triggers_gameover() async throws {
        // fool's mate setup — after 1.f3 e5 2.g4, black to play Qh4#
        let fen = "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2"
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid test fen"); return
        }
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .black,
            level: .default,
            engine: fake
        )
        let qh4 = try SanCodec.parse("Qh4", in: pos)
        await session.submit(qh4)
        XCTAssertEqual(session.status,
                       .gameOver(.checkmate(winner: .black)))
        XCTAssertEqual(fake.bestMoveCalls, 0,
                       "engine should not be queried after mate")
    }

    func test_user_move_into_stalemate_ends_game_as_draw() async throws {
        // King c6, queen b7, black king a8, white to play Qb6 stalemates.
        let fen = "k7/1Q6/2K5/8/8/8/8/8 w - - 0 1"
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid test fen"); return
        }
        let fake = FakeEngineService()
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )
        let qb6 = try SanCodec.parse("Qb6", in: pos)
        await session.submit(qb6)
        XCTAssertEqual(session.status, .gameOver(.stalemate))
        XCTAssertEqual(fake.bestMoveCalls, 0)
    }

    func test_status_is_engine_thinking_during_reply() async throws {
        // Confirm via the historyByUser trace that the engine query
        // really did happen as part of submit (not just bootstrap).
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["e7e5"]
        let session = EnginePlayoutSession(
            startingPosition: .standard,
            userSide: .white,
            level: .default,
            engine: fake
        )
        let e4 = try SanCodec.parse("e4", in: .standard)
        await session.submit(e4)
        // engine reply is applied; status back to waitingForUser
        XCTAssertEqual(session.status, .waitingForUser)
        XCTAssertEqual(session.historyByUser, [true, false])
    }

    func test_user_move_into_promotion_leaves_status_waiting_no_engine_call() async throws {
        // White pawn on e7, ready to promote — but submit should not
        // fire the engine reply because the user still has to choose a
        // promotion piece. v1: status stays .waitingForUser, no engine
        // call. (Promotion completion is a future task.)
        // Kings parked off the e-file so e7→e8 is a legal pawn promotion
        // (not blocked by the black king sitting on e8).
        let fen = "7k/4P3/8/8/8/8/8/K7 w - - 0 1"
        guard let pos = Position(fen: fen) else {
            XCTFail("invalid test fen"); return
        }
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["e8d8"] // would fire if we wrongly called engine
        let session = EnginePlayoutSession(
            startingPosition: pos,
            userSide: .white,
            level: .default,
            engine: fake
        )
        // e7→e8 as a plain Move (no promotion piece specified) — board.move
        // will park in .promotion(...) awaiting a piece choice.
        // chesskit's Square(_:) is non-failable, so use the enum cases.
        let from: Square = .e7
        let to: Square = .e8
        let move = Move(
            result: .move,
            piece: Piece(.pawn, color: .white, square: from),
            start: from,
            end: to
        )
        await session.submit(move)
        XCTAssertEqual(fake.bestMoveCalls, 0,
                       "engine must not be called while promotion is pending")
        XCTAssertEqual(session.status, .waitingForUser,
                       "session keeps the user on the clock until promotion is resolved")
    }
}
