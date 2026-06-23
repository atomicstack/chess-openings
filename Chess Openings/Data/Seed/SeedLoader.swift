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

        // Validate every ply in the new seed BEFORE mutating any state.
        // This way a malformed seed throws cleanly and the database is
        // left exactly as it was (no partial wipe + half-import).
        for o in dto.openings {
            for l in o.lines {
                var pos = Position.standard
                for (pi, ply) in l.plies.enumerated() {
                    do {
                        let m = try SanCodec.parse(ply.san, in: pos)
                        var board = Board(position: pos)
                        _ = board.move(pieceAt: m.start, to: m.end)
                        pos = board.position
                    } catch {
                        throw SeedError.invalidSanAt(
                            opening: o.name, line: l.name, index: pi,
                            san: ply.san, underlying: error
                        )
                    }
                }
            }
        }

        // Upsert by stable key. Goal: re-seed must preserve attached
        // `LineProgress` (correctStreak, isLearned, mistakes log) so a
        // catalogue update — renames, deeper plies, added lines — never
        // wipes the user's drill history. This explicitly replaces the
        // earlier wipe-then-reinsert flow; see CLAUDE.md "seed pipeline"
        // for why the version bump still drives the migration.
        let existingSeededOpenings = try context.fetch(
            FetchDescriptor<Opening>(predicate: #Predicate { $0.isSeed == true })
        )
        var openingsByName: [String: Opening] = Dictionary(
            uniqueKeysWithValues: existingSeededOpenings.map { ($0.name, $0) }
        )
        var seenOpeningNames: Set<String> = []

        for o in dto.openings {
            seenOpeningNames.insert(o.name)
            let sideEnum: Side = (o.side == "black") ? .black : .white

            let opening: Opening
            if let existing = openingsByName[o.name] {
                opening = existing
                // Update opening-level fields in place — name stays the
                // same (matching key); the rest can shift between seed
                // versions without losing the row's identity.
                opening.eco = o.eco
                opening.side = sideEnum
                opening.rootFen = o.rootFen
                opening.openingDescription = o.description
                opening.isSeed = true
            } else {
                opening = Opening(
                    name: o.name, eco: o.eco, side: sideEnum,
                    rootFen: o.rootFen, openingDescription: o.description, isSeed: true
                )
                context.insert(opening)
                openingsByName[o.name] = opening
            }

            // Index existing lines by stableKey so we can match the DTO.
            var existingByKey: [String: Line] = [:]
            var existingWithoutKey: [Line] = []
            for line in opening.lines {
                if let k = line.stableKey {
                    existingByKey[k] = line
                } else {
                    existingWithoutKey.append(line)
                }
            }

            // One-shot migration: legacy seed versions stored Lines
            // without a stableKey. Try to match each keyless row to a
            // DTO line by comparing their UCI ply prefix — the rootSan
            // + fork plies uniquely identify the line regardless of
            // walks shifting deeper, and they're identical in v3/v4
            // for any cache-stable opening. A successful match
            // backfills `stableKey` so the rest of the upsert path
            // (and every future re-seed) treats the row as matched
            // instead of orphaned.
            if !existingWithoutKey.isEmpty {
                var taken: Set<String> = []
                for legacy in existingWithoutKey {
                    let mine = legacy.plies.map { $0.uci }
                    for dtoLine in o.lines {
                        guard let key = dtoLine.stableKey,
                              !taken.contains(key),
                              dtoLine.source == legacy.source else { continue }
                        let theirs = dtoLine.plies.map { $0.uci }
                        let cmp = min(mine.count, theirs.count)
                        guard cmp > 0,
                              Array(mine[0..<cmp]) == Array(theirs[0..<cmp]) else { continue }
                        legacy.stableKey = key
                        existingByKey[key] = legacy
                        taken.insert(key)
                        break
                    }
                }
                existingWithoutKey.removeAll { $0.stableKey != nil }
            }

            var seenLineKeys: Set<String> = []
            for l in o.lines {
                let key = l.stableKey
                if let key, let existing = existingByKey[key] {
                    // Update-in-place — `mastery` relationship untouched
                    existing.name = l.name
                    existing.plies = l.plies
                    existing.tags = l.tags
                    existing.source = l.source
                    seenLineKeys.insert(key)
                } else {
                    let line = Line(
                        name: l.name, plies: l.plies, tags: l.tags,
                        source: l.source, stableKey: key
                    )
                    line.mastery = LineProgress()
                    line.opening = opening
                    opening.lines.append(line)
                    if let key { seenLineKeys.insert(key) }
                }
            }

            // Delete seeded lines that the new DTO no longer carries —
            // both keyed-but-orphaned and any keyless legacy rows (which
            // can no longer be matched against anything).
            let toDelete = existingByKey
                .filter { !seenLineKeys.contains($0.key) }
                .map { $0.value }
                + existingWithoutKey
            for line in toDelete {
                if let idx = opening.lines.firstIndex(where: { $0.id == line.id }) {
                    opening.lines.remove(at: idx)
                }
                context.delete(line)
            }
        }

        // Delete seeded openings the new DTO no longer carries.
        for (name, opening) in openingsByName where !seenOpeningNames.contains(name) {
            context.delete(opening)
        }

        settings.seededVersion = dto.version
        try context.save()
    }
}
