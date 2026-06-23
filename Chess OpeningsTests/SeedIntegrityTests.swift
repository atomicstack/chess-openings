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
        // Catalogue grows over time — assert a lower bound rather than
        // pinning to a specific count, so adding new openings doesn't
        // require touching the integrity test.
        XCTAssertGreaterThanOrEqual(dto.openings.count, 16,
                                    "expected at least the original 16 catalogue openings")

        for opening in dto.openings {
            let masters = opening.lines.filter { $0.source == .masters }
            let open    = opening.lines.filter { $0.source == .open }
            XCTAssertFalse(masters.isEmpty, "\(opening.name) missing masters lines")
            XCTAssertFalse(open.isEmpty,    "\(opening.name) missing open lines")
            // Some entries (e.g. the new two-knights sub-variations)
            // use lineCount=2 → 4 lines total, which is fine. Just
            // require at least one of each source.
            XCTAssertGreaterThanOrEqual(opening.lines.count, 2,
                                        "\(opening.name) has \(opening.lines.count) lines")
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
