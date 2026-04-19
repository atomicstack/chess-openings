import Foundation
import SwiftData
import ChessKit

struct SeedLoader {
    enum SeedError: Error {
        case missingBundleResource
        case decode(Error)
        case invalidSanAt(opening: String, line: String, index: Int, san: String, underlying: Error?)
    }

    func seedIfNeeded(context: ModelContext, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "openings", withExtension: "json") else {
            throw SeedError.missingBundleResource
        }
        let data = try Data(contentsOf: url)
        let dto: SeedDTO
        do { dto = try JSONDecoder().decode(SeedDTO.self, from: data) }
        catch { throw SeedError.decode(error) }

        // get or create settings row
        let settings: UserSettings
        if let existing = try context.fetch(FetchDescriptor<UserSettings>()).first {
            settings = existing
        } else {
            settings = UserSettings()
            context.insert(settings)
        }

        if settings.seededVersion >= dto.version {
            return
        }

        // wipe existing seed openings (cascades to lines + progress)
        let stale = try context.fetch(FetchDescriptor<Opening>(predicate: #Predicate { $0.isSeed == true }))
        for o in stale { context.delete(o) }

        for o in dto.openings {
            let sideEnum: Side = (o.side == "black") ? .black : .white
            let opening = Opening(
                name: o.name, eco: o.eco, side: sideEnum,
                rootFen: o.rootFen, openingDescription: o.description, isSeed: true
            )
            for l in o.lines {
                // validate plies before inserting
                var pos = Position.standard
                for (pi, ply) in l.plies.enumerated() {
                    do {
                        let m = try SanCodec.parse(ply.san, in: pos)
                        var board = Board(position: pos)
                        _ = board.move(pieceAt: m.start, to: m.end)
                        pos = board.position
                    } catch {
                        throw SeedError.invalidSanAt(
                            opening: o.name, line: l.name, index: pi, san: ply.san, underlying: error
                        )
                    }
                }
                let line = Line(name: l.name, plies: l.plies, tags: l.tags, source: l.source)
                line.mastery = LineProgress()
                line.opening = opening
                opening.lines.append(line)
            }
            context.insert(opening)
        }
        settings.seededVersion = dto.version
        try context.save()
    }
}
