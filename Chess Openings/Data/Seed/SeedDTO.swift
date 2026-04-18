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
}
