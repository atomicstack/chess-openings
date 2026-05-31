import Foundation
import ChessKit

extension EnginePlayoutSession {
    /// Map a chesskit `Board.State` to one of our `GameOverReason`s.
    /// Returns `nil` if the game is still active or merely in check —
    /// callers continue play in that case. `.promotion` returns `nil`
    /// here too; promotion handling is a v1 limitation (engine moves
    /// that promote are rejected by `parseUCI`; user promotion moves
    /// leave the session waiting for the user to commit a choice).
    // FIXME: promotion handling deferred to post-v1
    static func reason(forBoardState state: Board.State) -> GameOverReason? {
        switch state {
        case .checkmate(let losingColor):
            // the winner is the side NOT in mate
            return .checkmate(winner: losingColor.side.opposite)
        case .draw(let reason):
            switch reason {
            case .stalemate:             return .stalemate
            case .fiftyMoves:            return .fiftyMoveRule
            case .repetition:            return .threefoldRepetition
            case .insufficientMaterial:  return .insufficientMaterial
            case .agreement:             return .drawAgreed
            }
        case .active, .check, .promotion:
            return nil
        }
    }
}
