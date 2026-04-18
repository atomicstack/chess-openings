import Foundation
import ChessKit

/// Replays a list of SAN plies from the standard starting position
/// and returns the resulting `Position` along with the parsed `Move`
/// for each ply, in order.
enum PositionBuilder {
    enum BuildError: Error, Equatable {
        /// The ply at index `ply` (0-based, as passed in) could not be
        /// parsed as a legal SAN move in the position reached so far.
        case illegal(ply: Int, san: String)
    }

    /// Build a position by applying SAN plies one after another,
    /// starting from `Position.standard`.
    ///
    /// - parameter plies: SAN strings in order (white first).
    /// - returns: The final `Position` and the array of parsed `Move`s.
    /// - throws: `BuildError.illegal` on the first ply that cannot be parsed.
    static func build(fromSan plies: [String]) throws -> (Position, [Move]) {
        var board = Board(position: .standard)
        var moves: [Move] = []

        for (i, san) in plies.enumerated() {
            guard let parsed = SANParser.parse(move: san, in: board.position) else {
                throw BuildError.illegal(ply: i, san: san)
            }
            guard let applied = board.move(pieceAt: parsed.start, to: parsed.end) else {
                throw BuildError.illegal(ply: i, san: san)
            }
            moves.append(applied)
        }

        return (board.position, moves)
    }
}
