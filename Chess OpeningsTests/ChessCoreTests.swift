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

    func test_bookply_codable_round_trip() throws {
        let ply = BookPly(san: "e4", uci: "e2e4", annotation: "king pawn", alternativeSans: [])
        let data = try JSONEncoder().encode(ply)
        let decoded = try JSONDecoder().decode(BookPly.self, from: data)
        XCTAssertEqual(decoded.san, "e4")
        XCTAssertEqual(decoded.uci, "e2e4")
        XCTAssertEqual(decoded.annotation, "king pawn")
        XCTAssertTrue(decoded.alternativeSans.isEmpty)
    }

    func test_line_source_decodes_from_string() throws {
        let json = #""masters""#.data(using: .utf8)!
        let masters = try JSONDecoder().decode(LineSource.self, from: json)
        XCTAssertEqual(masters, .masters)

        let json2 = #""open""#.data(using: .utf8)!
        let open = try JSONDecoder().decode(LineSource.self, from: json2)
        XCTAssertEqual(open, .open)
    }

    func test_line_source_encodes_to_string() throws {
        let data = try JSONEncoder().encode(LineSource.masters)
        XCTAssertEqual(String(data: data, encoding: .utf8), #""masters""#)
    }

    func test_seed_line_dto_decodes_source_field() throws {
        let json = """
        { "name": "g6", "plies": [], "tags": [], "source": "open" }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(SeedLineDTO.self, from: json)
        XCTAssertEqual(dto.source, .open)
    }

    func test_seed_line_dto_defaults_to_masters_when_source_missing() throws {
        let json = """
        { "name": "g6", "plies": [], "tags": [] }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(SeedLineDTO.self, from: json)
        XCTAssertEqual(dto.source, .masters)
    }

    func test_line_model_stores_source() {
        let line = Line(name: "g6", plies: [], source: .open)
        XCTAssertEqual(line.source, .open)
    }

    func test_line_model_defaults_to_masters() {
        let line = Line(name: "g6", plies: [])
        XCTAssertEqual(line.source, .masters)
    }

    func test_user_settings_defaults_seeded_version_to_zero() {
        let s = UserSettings()
        XCTAssertEqual(s.seededVersion, 0)
    }
}
