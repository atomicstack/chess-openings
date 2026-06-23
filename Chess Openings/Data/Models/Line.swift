import Foundation
import SwiftData

@Model
final class Line {
    @Attribute(.unique) var id: UUID
    var opening: Opening?
    var name: String
    var pliesData: Data                       // JSON-encoded [BookPly]
    var tagsCSV: String                       // comma-joined
    var sourceRaw: String = LineSource.masters.rawValue
    /// Stable identity across seed versions — `<openingName>|<source>|<forkUci>`.
    /// `SeedLoader` uses this to upsert lines on a version bump, preserving
    /// the attached `LineProgress` (correctStreak, isLearned, mistakes, …).
    /// Optional so older rows / user-created lines without one still decode.
    var stableKey: String? = nil
    @Relationship(deleteRule: .cascade, inverse: \LineProgress.line) var mastery: LineProgress?

    var plies: [BookPly] {
        get { (try? JSONDecoder().decode([BookPly].self, from: pliesData)) ?? [] }
        set { pliesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    var tags: [String] {
        get { tagsCSV.isEmpty ? [] : tagsCSV.split(separator: ",").map(String.init) }
        set { tagsCSV = newValue.joined(separator: ",") }
    }
    var source: LineSource {
        get { LineSource(rawValue: sourceRaw) ?? .masters }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        plies: [BookPly],
        tags: [String] = [],
        source: LineSource = .masters,
        stableKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.pliesData = (try? JSONEncoder().encode(plies)) ?? Data()
        self.tagsCSV = tags.joined(separator: ",")
        self.sourceRaw = source.rawValue
        self.stableKey = stableKey
    }
}
