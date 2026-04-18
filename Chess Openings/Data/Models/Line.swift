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
        source: LineSource = .masters
    ) {
        self.id = id
        self.name = name
        self.pliesData = (try? JSONEncoder().encode(plies)) ?? Data()
        self.tagsCSV = tags.joined(separator: ",")
        self.sourceRaw = source.rawValue
    }
}
