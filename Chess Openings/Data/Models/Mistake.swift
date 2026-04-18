import Foundation

struct Mistake: Codable, Hashable, Sendable {
    var ply: BookPly
    var playedSan: String
    var at: Date
}
