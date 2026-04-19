import Foundation
import ChessKit

/// The discrete sound events the app can play. One raw value per file
/// under `Resources/Sounds/`.
enum SoundEffect: String, Sendable, CaseIterable {
    case moveSelf, moveOpponent, capture, castle, promote, moveCheck
    case illegal, incorrect, correct, puzzleCorrect, achievement
    case gameStart, gameEnd, click
    /// Played when the user completes a full drill line.
    case lineVictory
    /// Played when the user attempts an off-book move in a drill.
    case wrongMove

    /// Basename (without extension) of the mp3 inside the app bundle.
    var fileName: String {
        switch self {
        case .moveSelf:       return "move-self"
        case .moveOpponent:   return "move-opponent"
        case .capture:        return "capture"
        case .castle:         return "castle"
        case .promote:        return "promote"
        case .moveCheck:      return "move-check"
        case .illegal:        return "illegal"
        case .incorrect:      return "incorrect"
        case .correct:        return "correct"
        case .puzzleCorrect:  return "puzzle-correct"
        case .achievement:    return "achievement"
        case .gameStart:      return "game-start"
        case .gameEnd:        return "game-end"
        case .click:          return "click"
        case .lineVictory:    return "result-good-2-15"
        case .wrongMove:      return "incorrect-2-15"
        }
    }

    /// Pure classifier: given a `Move` and the positions before/after it,
    /// decide which sound to play. Check overrides everything else; then
    /// castle, then promote, then capture, then a plain move (whose
    /// flavour depends on whether the user or the book played it).
    static func forMove(_ move: Move, pre: Position, post: Position, byUser: Bool) -> SoundEffect {
        _ = pre
        _ = post
        if move.isCheck      { return .moveCheck }
        if move.isCastle     { return .castle }
        if move.isPromotion  { return .promote }
        if move.isCapture    { return .capture }
        return byUser ? .moveSelf : .moveOpponent
    }
}

// MARK: - chesskit Move classification helpers

private extension Move {
    /// chesskit's `checkState` covers `.check` and `.checkmate`.
    var isCheck: Bool {
        switch checkState {
        case .check, .checkmate: return true
        case .none, .stalemate:  return false
        }
    }

    /// chesskit encodes the move flavour in `result`.
    var isCastle: Bool {
        if case .castle = result { return true }
        return false
    }

    var isCapture: Bool {
        if case .capture = result { return true }
        return false
    }

    /// Promotion is signalled via the `promotedPiece` property.
    var isPromotion: Bool {
        promotedPiece != nil
    }
}
