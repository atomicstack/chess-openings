import Foundation

struct SeedDTO: Codable {
    let version: Int
    let openings: [SeedOpeningDTO]
}

struct SeedOpeningDTO: Codable {
    let name: String
    let eco: String?
    let side: String
    let rootFen: String
    let description: String?
    let isSeed: Bool
    let lines: [SeedLineDTO]
}

struct SeedLineDTO: Codable {
    let name: String
    let plies: [BookPly]
    let tags: [String]
    let source: LineSource
    /// Optional stable identity (`<openingName>|<source>|<forkUci>`) that
    /// `SeedLoader` uses to match new seed lines against existing rows
    /// so a version bump preserves `LineProgress`. Older seed JSON files
    /// (and user-created lines) won't carry one — those re-seed as fresh.
    let stableKey: String?

    enum CodingKeys: String, CodingKey {
        case name, plies, tags, source, stableKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.plies = try c.decode([BookPly].self, forKey: .plies)
        self.tags = try c.decode([String].self, forKey: .tags)
        self.source = try c.decodeIfPresent(LineSource.self, forKey: .source) ?? .masters
        self.stableKey = try c.decodeIfPresent(String.self, forKey: .stableKey)
    }
}
