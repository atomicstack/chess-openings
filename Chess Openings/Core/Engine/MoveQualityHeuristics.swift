import Foundation
import ChessKit

/// Standard centipawn-scale material values for each chess piece kind.
/// Used by the brilliant-move heuristic to compare moved-piece value
/// against attacker/captured-piece values.
enum PieceMaterial {
    static func value(of kind: Piece.Kind) -> Int {
        switch kind {
        case .pawn:   return 1
        case .knight: return 3
        case .bishop: return 3
        case .rook:   return 5
        case .queen:  return 9
        case .king:   return 0
        }
    }
}

enum SquareAttacks {
    /// All squares occupied by `color`'s pieces that attack `target`
    /// in `position`. Uses chesskit's legal-move generation: for each
    /// opponent piece, asks whether the target is among its legal
    /// destinations. This filters out moves that would leave the
    /// opponent king in check — which is acceptable for our purposes
    /// (we want real capture threats).
    static func attackers(
        of target: Square,
        by color: Piece.Color,
        in position: Position
    ) -> [Square] {
        let board = Board(position: position)
        return position.pieces
            .filter { $0.color == color }
            .compactMap { piece in
                board.legalMoves(forPieceAt: piece.square)
                    .contains(target) ? piece.square : nil
            }
    }
}

/// Whether `userMove` is a brilliant-candidate per chess.com-style rules.
/// `pre` is the position before the user moved, `post` is after. `bestUci`
/// is the engine's recommended best move in long-algebraic form; if nil,
/// the move is not considered brilliant.
///
/// All six criteria must hold:
///  1. the user played the engine's best move,
///  2. the user wasn't already crushing (bestEvalCp < +300),
///  3. the position is still winning or equal after best defense,
///  4. the moved piece is at least a knight (value >= 3),
///  5. captured value (if any) < moved piece value (not a fair trade),
///  6. the destination is attacked by an opponent piece of lower value
///     than the moved piece (so the exchange would lose material).
@MainActor
func isBrilliantCandidate(
    userMove: Move,
    pre: Position,
    post: Position,
    userSide: Side,
    bestUci: String?,
    bestEvalCp: Int,
    actualEvalCp: Int
) -> Bool {
    // 1. user played the engine's best move
    guard let bestUci, bestUci.count >= 4 else { return false }
    let bestFromStr = String(bestUci.prefix(2))
    let bestToStr = String(bestUci.dropFirst(2).prefix(2))
    let bestFrom = Square(bestFromStr)
    let bestTo = Square(bestToStr)
    guard userMove.start == bestFrom, userMove.end == bestTo else { return false }
    // 2. not already crushing
    guard bestEvalCp < 300 else { return false }
    // 3. still winning or equal
    guard actualEvalCp >= 0 else { return false }
    // 4. moved piece is at least a knight
    guard let movedPieceKind = pre.piece(at: userMove.start)?.kind else { return false }
    let movedValue = PieceMaterial.value(of: movedPieceKind)
    guard movedValue >= 3 else { return false }
    // 5. captured value (if any) < moved value (not a fair trade)
    let capturedValue = pre.piece(at: userMove.end).map { PieceMaterial.value(of: $0.kind) } ?? 0
    guard capturedValue < movedValue else { return false }
    // 6. destination is attacked by an opponent piece of value LESS than moved value
    let opponentColor: Piece.Color = userSide == .white ? .black : .white
    let attackerSquares = SquareAttacks.attackers(of: userMove.end, by: opponentColor, in: post)
    let minAttackerValue = attackerSquares
        .compactMap { post.piece(at: $0).map { PieceMaterial.value(of: $0.kind) } }
        .min()
    guard let minAttacker = minAttackerValue, minAttacker < movedValue else { return false }
    return true
}
