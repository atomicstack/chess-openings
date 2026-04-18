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

        XCTAssertEqual(dto.openings.count, 16)
        for opening in dto.openings {
            XCTAssert(opening.lines.count >= 4 && opening.lines.count <= 5,
                      "\(opening.name) has \(opening.lines.count) lines")
            for line in opening.lines {
                XCTAssert(line.plies.count <= 20,
                          "\(opening.name)/\(line.name) has \(line.plies.count) plies")
                // replay each ply
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
