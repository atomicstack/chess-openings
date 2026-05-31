import Foundation

enum PlayoutStatus: Equatable, Sendable {
    case waitingForUser
    case engineThinking
    case drawOffered(byUser: Bool)
    case gameOver(GameOverReason)
}

enum GameOverReason: Equatable, Sendable {
    case checkmate(winner: Side)
    case stalemate
    case fiftyMoveRule
    case threefoldRepetition
    case insufficientMaterial
    case drawAgreed
    case userResigned
    case engineResigned(accepted: Bool?)
}
