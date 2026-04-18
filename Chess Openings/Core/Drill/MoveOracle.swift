import Foundation
import ChessKit

protocol MoveOracle: Sendable {
    func acceptableMoves(at position: Position, history: [Move]) async -> [BookCandidate]
}
