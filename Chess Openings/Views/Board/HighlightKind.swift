import SwiftUI

enum HighlightKind {
    case selected, legalTarget, hintFrom, hintTo, hintFromPulse, lastMove, captureTarget

    /// Fill color for rectangle-style highlights. `captureTarget` is
    /// rendered as a stroked circle instead (see `SquareView`), and
    /// `hintFromPulse` is rendered as a hue-rotating overlay driven by
    /// a `TimelineView` — both bypass the static-fill path.
    var overlayColor: Color {
        switch self {
        case .selected:       return .blue.opacity(0.35)
        case .legalTarget:    return .blue.opacity(0.18)
        case .hintFrom:       return Color(red: 0.55, green: 0.92, blue: 0.55).opacity(0.50)
        case .hintTo:         return Color(red: 0.55, green: 0.92, blue: 0.55).opacity(0.30)
        case .hintFromPulse:  return .clear
        case .lastMove:       return Color(red: 0.95, green: 0.90, blue: 0.50).opacity(0.40)
        case .captureTarget:  return .clear
        }
    }
}
