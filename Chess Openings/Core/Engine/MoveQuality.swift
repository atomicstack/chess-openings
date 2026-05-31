import Foundation
import SwiftUI

/// Lichess/chess.com-style move-quality buckets. Reported on user
/// moves only during engine playout.
enum MoveQuality: Equatable, Sendable {
    case best
    case excellent
    case good
    case inaccuracy
    case mistake
    case blunder
    case miss

    /// SF Symbol name for the badge icon.
    var iconName: String {
        switch self {
        case .best:       return "checkmark.seal.fill"
        case .excellent:  return "star.fill"
        case .good:       return "checkmark.circle.fill"
        case .inaccuracy: return "questionmark.circle.fill"
        case .mistake:    return "exclamationmark.circle.fill"
        case .blunder:    return "xmark.circle.fill"
        case .miss:       return "eye.slash.fill"
        }
    }

    var color: Color {
        switch self {
        case .best:       return .green
        case .excellent:  return .mint
        case .good:       return .blue
        case .inaccuracy: return .yellow
        case .mistake:    return .orange
        case .blunder:    return .red
        case .miss:       return .purple
        }
    }

    /// Classify based on the centipawn drop relative to the engine's
    /// best move at the same position. Both inputs are from the user's
    /// POV. `bestEvalIsWinning` is true when the engine considered the
    /// position winning for the user (≥ +200 cp or mate); when true,
    /// any drop ≥ 300 is upgraded to `.miss` instead of `.blunder`.
    static func classify(
        bestEvalCp: Int,
        actualEvalCp: Int,
        bestEvalIsWinning: Bool
    ) -> MoveQuality {
        let drop = bestEvalCp - actualEvalCp
        if bestEvalIsWinning && drop >= 300 { return .miss }
        switch drop {
        case ..<5:    return .best
        case ..<20:   return .excellent
        case ..<50:   return .good
        case ..<100:  return .inaccuracy
        case ..<300:  return .mistake
        default:      return .blunder
        }
    }
}

extension EngineEvaluation {
    /// Clamp mate scores to ±5000 cp so they slot into the same
    /// integer eval domain used by `MoveQuality.classify`.
    var clampedCp: Int {
        switch self {
        case .cp(let v):   return v
        case .mate(let n):
            if n > 0 { return 5000 }
            if n < 0 { return -5000 }
            return 0
        }
    }
}
