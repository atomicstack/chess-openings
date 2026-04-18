import SwiftUI

enum HighlightKind {
    case selected, legalTarget, hintFrom, hintTo, lastMove

    var overlayColor: Color {
        switch self {
        case .selected:     return .blue.opacity(0.35)
        case .legalTarget:  return .blue.opacity(0.18)
        case .hintFrom:     return .orange.opacity(0.45)
        case .hintTo:       return .orange.opacity(0.25)
        case .lastMove:     return .yellow.opacity(0.20)
        }
    }
}
