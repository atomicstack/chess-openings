import Foundation

enum Side: String, Codable, Sendable, CaseIterable {
    case white
    case black

    var opposite: Side {
        switch self {
        case .white: return .black
        case .black: return .white
        }
    }
}
