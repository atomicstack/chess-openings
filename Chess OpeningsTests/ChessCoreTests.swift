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
}
