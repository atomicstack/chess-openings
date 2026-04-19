import XCTest
import ChessKit
@testable import Chess_Openings

final class SeedIntegrityTests: XCTestCase {
    func test_bundled_seed_loads_and_every_line_is_legal() throws {
        let url = Bundle(for: Self.self).url(forResource: "openings", withExtension: "json")
            ?? Bundle.main.url(forResource: "openings", withExtension: "json")
        guard let url else { XCTFail("openings.json not in bundle"); return }
        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(SeedDTO.self, from: data)

        XCTAssertGreaterThanOrEqual(dto.version, 2, "seed version should be >=2 after dual-source migration")
        XCTAssertEqual(dto.openings.count, 16)

        for opening in dto.openings {
            let masters = opening.lines.filter { $0.source == .masters }
            let open    = opening.lines.filter { $0.source == .open }
            XCTAssertFalse(masters.isEmpty, "\(opening.name) missing masters lines")
            XCTAssertFalse(open.isEmpty,    "\(opening.name) missing open lines")
            XCTAssertTrue(opening.lines.count >= 8 && opening.lines.count <= 10,
                          "\(opening.name) has \(opening.lines.count) lines, expected 8-10")
            for line in opening.lines {
                XCTAssertTrue(line.plies.count <= 20,
                              "\(opening.name)/\(line.name) has \(line.plies.count) plies")
                var pos = Position.standard
                for (i, ply) in line.plies.enumerated() {
                    guard let m = SANParser.parse(move: ply.san, in: pos) else {
                        return XCTFail("\(opening.name)/\(line.name): illegal san '\(ply.san)' at ply \(i)")
                    }
                    var board = Board(position: pos)
                    _ = board.move(pieceAt: m.start, to: m.end)
                    pos = board.position
                }
            }
        }
    }
}
