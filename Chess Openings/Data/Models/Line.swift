import Foundation
import SwiftData

@Model
final class Line {
    @Attribute(.unique) var id: UUID
    var opening: Opening?
    var name: String
    var pliesData: Data                       // JSON-encoded [BookPly]
    var tagsCSV: String                       // comma-joined
    @Relationship(deleteRule: .cascade, inverse: \LineProgress.line) var mastery: LineProgress?

    var plies: [BookPly] {
        get { (try? JSONDecoder().decode([BookPly].self, from: pliesData)) ?? [] }
        set { pliesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    var tags: [String] {
        get { tagsCSV.isEmpty ? [] : tagsCSV.split(separator: ",").map(String.init) }
        set { tagsCSV = newValue.joined(separator: ",") }
    }

    init(id: UUID = UUID(), name: String, plies: [BookPly], tags: [String] = []) {
        self.id = id
        self.name = name
        self.pliesData = (try? JSONEncoder().encode(plies)) ?? Data()
        self.tagsCSV = tags.joined(separator: ",")
    }
}
