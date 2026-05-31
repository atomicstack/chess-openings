import Foundation
import SwiftUI

/// Lichess/chess.com-style move-quality buckets. Reported on user
/// moves only during engine playout.
enum MoveQuality: Equatable, Sendable {
    case brilliant
    case best
    case excellent
    case good
    case inaccuracy
    case mistake
    case blunder
    case miss

    /// What's drawn inside the colored circle on a badge. Either a
    /// short text glyph (e.g. "!!", "?!") rendered as `Text`, or an
    /// SF Symbol name rendered as `Image(systemName:)`.
    enum Glyph: Equatable, Sendable {
        case text(String)
        case symbol(String)
    }

    /// chess.com-style glyph for the badge — the colour, name, and
    /// glyph mapping mirror `docs/move-quality-reference.html`.
    var glyph: Glyph {
        switch self {
        case .brilliant:  return .text("!!")
        case .best:       return .symbol("star.fill")
        case .excellent:  return .symbol("hand.thumbsup.fill")
        case .good:       return .symbol("checkmark")
        case .inaccuracy: return .text("?!")
        case .mistake:    return .text("?")
        case .blunder:    return .text("??")
        case .miss:       return .symbol("xmark")
        }
    }

    /// chess.com-style palette. Eyeballed from screenshots; kept as
    /// hex literals so the badges read identically across light and
    /// dark mode (SwiftUI's stock `.green` etc. shift with the
    /// system appearance).
    var color: Color {
        switch self {
        case .brilliant:  return Color(red: 0x1B/255, green: 0xA1/255, blue: 0xA1/255)
        case .best:       return Color(red: 0x95/255, green: 0xBB/255, blue: 0x4A/255)
        case .excellent:  return Color(red: 0x95/255, green: 0xBB/255, blue: 0x4A/255)
        case .good:       return Color(red: 0x95/255, green: 0xAF/255, blue: 0x80/255)
        case .inaccuracy: return Color(red: 0xF7/255, green: 0xC2/255, blue: 0x45/255)
        case .mistake:    return Color(red: 0xFF/255, green: 0xA4/255, blue: 0x59/255)
        case .blunder:    return Color(red: 0xFA/255, green: 0x41/255, blue: 0x2D/255)
        case .miss:       return Color(red: 0xFF/255, green: 0x77/255, blue: 0x69/255)
        }
    }

    /// Classify based on the centipawn drop relative to the engine's
    /// best move at the same position. Both inputs are from the user's
    /// POV. `bestEvalIsWinning` is true when the engine considered the
    /// position winning for the user (≥ +200 cp or mate); when true,
    /// any drop ≥ 300 is upgraded to `.miss` instead of `.blunder`.
    /// When `isBrilliantCandidate` is true AND the drop is small enough
    /// to otherwise qualify as `.best`, the move is upgraded to
    /// `.brilliant` (chess.com-style sacrifice detection — see
    /// `MoveQualityHeuristics.swift`).
    static func classify(
        bestEvalCp: Int,
        actualEvalCp: Int,
        bestEvalIsWinning: Bool,
        isBrilliantCandidate: Bool = false
    ) -> MoveQuality {
        let drop = bestEvalCp - actualEvalCp
        if isBrilliantCandidate && drop < 5 { return .brilliant }
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
