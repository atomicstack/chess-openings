import Foundation
import ChessKit

/// Codable bridge for a chesskit `Move`. Stores only what's needed to
/// reconstruct the move via `Board.move(pieceAt:to:)` + (optionally)
/// `Board.completePromotion(of:to:)` — chesskit's `Move` itself isn't
/// directly Codable, but the start/end algebraic squares and an
/// optional promotion kind cover everything we need.
struct StoredMove: Codable, Equatable, Hashable {
    /// Algebraic notation of the start square, e.g. "e2".
    let from: String
    /// Algebraic notation of the end square, e.g. "e4".
    let to: String
    /// `nil` for non-promotions; otherwise the chesskit kind name,
    /// e.g. "queen" / "knight" / "bishop" / "rook".
    let promotion: String?
    /// `true` for moves the user played, `false` for engine replies.
    /// Mirrors `EnginePlayoutSession.historyByUser`.
    let byUser: Bool
}

extension StoredMove {
    init(move: Move, byUser: Bool) {
        self.from = move.start.notation
        self.to = move.end.notation
        self.promotion = move.promotedPiece.map { Self.kindString($0.kind) }
        self.byUser = byUser
    }

    /// Reconstruct the chesskit `Move` against the given starting
    /// position. Returns `nil` if the algebraic strings are malformed
    /// or the move is illegal at `pre`.
    func reconstruct(at pre: Position) -> (move: Move, byUser: Bool)? {
        guard Self.isAlgebraic(from), Self.isAlgebraic(to) else { return nil }
        let fromSq = Square(from)
        let toSq = Square(to)
        var board = Board(position: pre)
        guard let pending = board.move(pieceAt: fromSq, to: toSq) else {
            return nil
        }
        if case .promotion = board.state,
           let promo = promotion,
           let kind = Self.kindFromString(promo) {
            let finalMove = board.completePromotion(of: pending, to: kind)
            return (finalMove, byUser)
        }
        return (pending, byUser)
    }

    // MARK: - helpers

    /// chesskit's `Square(_ String)` snaps malformed input to `.a1`;
    /// validate before we trust it.
    private static func isAlgebraic(_ s: String) -> Bool {
        guard s.count == 2 else { return false }
        let chars = Array(s)
        return ("a"..."h").contains(chars[0]) && ("1"..."8").contains(chars[1])
    }

    private static func kindString(_ kind: Piece.Kind) -> String {
        switch kind {
        case .pawn:   return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook:   return "rook"
        case .queen:  return "queen"
        case .king:   return "king"
        }
    }

    private static func kindFromString(_ s: String) -> Piece.Kind? {
        switch s {
        case "pawn":   return .pawn
        case "knight": return .knight
        case "bishop": return .bishop
        case "rook":   return .rook
        case "queen":  return .queen
        case "king":   return .king
        default:       return nil
        }
    }
}

extension Array where Element == StoredMove {
    /// Materialise the whole sequence into chesskit `Move`s by
    /// replaying it against an evolving `Board` starting from
    /// `start`. Returns `nil` on the first move that can't be
    /// reconstructed (defensive against a corrupted snapshot).
    func reconstruct(from start: Position) -> [(move: Move, byUser: Bool)]? {
        var pre = start
        var result: [(Move, Bool)] = []
        for stored in self {
            guard let (move, byUser) = stored.reconstruct(at: pre) else {
                return nil
            }
            var board = Board(position: pre)
            let pending = board.move(pieceAt: move.start, to: move.end)
            if case .promotion = board.state,
               let pending,
               let promo = move.promotedPiece {
                _ = board.completePromotion(of: pending, to: promo.kind)
            }
            pre = board.position
            result.append((move, byUser))
        }
        return result
    }
}
