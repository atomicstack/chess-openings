import Foundation
import ChessKit

struct LineBookOracle: MoveOracle {
    let plies: [BookPly]

    func acceptableMoves(at position: Position, history: [Move]) async -> [BookCandidate] {
        guard history.count < plies.count else { return [] }
        let nextPly = plies[history.count]
        guard let move = SANParser.parse(move: nextPly.san, in: position) else { return [] }
        return [BookCandidate(move: move, san: nextPly.san, annotation: nextPly.annotation)]
    }
}
