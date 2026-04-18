import Foundation

/// User-facing progress counter for a drill line. We count plies played
/// at the user's parity (even indices for white-side, odd for black-side)
/// so the counter reflects "my moves played / my moves in this line"
/// rather than total plies including the book's replies.
enum DrillProgress {
    static func userMoves(historyCount: Int, totalPlies: Int, side: Side) -> (played: Int, total: Int) {
        switch side {
        case .white:
            return ((historyCount + 1) / 2, (totalPlies + 1) / 2)
        case .black:
            return (historyCount / 2, totalPlies / 2)
        }
    }
}
