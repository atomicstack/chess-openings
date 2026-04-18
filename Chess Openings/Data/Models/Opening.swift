import Foundation
import SwiftData

@Model
final class Opening {
    @Attribute(.unique) var id: UUID
    var name: String
    var eco: String?
    var sideRaw: String
    var rootFen: String
    var openingDescription: String?
    var isSeed: Bool
    @Relationship(deleteRule: .cascade, inverse: \Line.opening) var lines: [Line]

    var side: Side {
        get { Side(rawValue: sideRaw) ?? .white }
        set { sideRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        eco: String?,
        side: Side,
        rootFen: String,
        openingDescription: String? = nil,
        isSeed: Bool,
        lines: [Line] = []
    ) {
        self.id = id
        self.name = name
        self.eco = eco
        self.sideRaw = side.rawValue
        self.rootFen = rootFen
        self.openingDescription = openingDescription
        self.isSeed = isSeed
        self.lines = lines
    }
}
