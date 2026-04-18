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

    enum CodingKeys: String, CodingKey {
        case name, plies, tags, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.plies = try c.decode([BookPly].self, forKey: .plies)
        self.tags = try c.decode([String].self, forKey: .tags)
        self.source = try c.decodeIfPresent(LineSource.self, forKey: .source) ?? .masters
    }
}
