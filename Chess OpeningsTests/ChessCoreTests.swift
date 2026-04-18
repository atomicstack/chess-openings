import XCTest
@testable import Chess_Openings

final class ChessCoreTests: XCTestCase {
    func test_side_opposite() {
        XCTAssertEqual(Side.white.opposite, .black)
        XCTAssertEqual(Side.black.opposite, .white)
    }

    func test_position_standard_starts_with_white_to_move() {
        let pos = Position.standard
        XCTAssertEqual(pos.sideToMove, .white)
    }

    func test_side_bridges_to_chesskit_color() {
        XCTAssertEqual(Side.white.ckColor, .white)
        XCTAssertEqual(Side.black.ckColor, .black)
    }

    func test_sancodec_parses_e4_from_start() throws {
        let pos = Position.standard
        let move = try SanCodec.parse("e4", in: pos)
        XCTAssertEqual(move.start.notation, "e2")
        XCTAssertEqual(move.end.notation, "e4")
    }

    func test_sancodec_round_trip_e4() throws {
        let pos = Position.standard
        let move = try SanCodec.parse("e4", in: pos)
        let san = SanCodec.format(move, in: pos)
        XCTAssertEqual(san, "e4")
    }

    func test_sancodec_rejects_illegal() {
        let pos = Position.standard
        XCTAssertThrowsError(try SanCodec.parse("e5", in: pos))
    }

    func test_positionbuilder_from_plies() throws {
        let plies = ["e4", "e5", "Nf3"]
        let (pos, moves) = try PositionBuilder.build(fromSan: plies)
        XCTAssertEqual(moves.count, 3)
        XCTAssertEqual(pos.sideToMove, .black)
    }

    func test_positionbuilder_rejects_illegal_ply_with_index() {
        let plies = ["e4", "e9"]
        XCTAssertThrowsError(try PositionBuilder.build(fromSan: plies)) { error in
            guard case PositionBuilder.BuildError.illegal(ply: let i, san: let s) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(i, 1)
            XCTAssertEqual(s, "e9")
        }
    }
}
