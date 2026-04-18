import Foundation
import ChessKit

/// Parse and format standard algebraic notation (SAN) moves
/// against a given `Position`.
///
/// This is a thin wrapper over chesskit's `SANParser` so the rest
/// of the app depends on a stable namespace of our own.
enum SanCodec {
    enum SanError: Error, Equatable {
        case invalidSan(String)
    }

    /// Parse `san` in the context of `position` and return the resulting move.
    ///
    /// - throws: `SanError.invalidSan` if the SAN is unrecognised or
    ///   illegal in `position`.
    static func parse(_ san: String, in position: Position) throws -> Move {
        guard let move = SANParser.parse(move: san, in: position) else {
            throw SanError.invalidSan(san)
        }
        return move
    }

    /// Format `move` as SAN.
    ///
    /// The chesskit converter does not require the position — disambiguation
    /// is already baked into the `Move`. The `position` parameter is kept
    /// in the signature for call-site symmetry with `parse(_:in:)` and to
    /// leave room for a future position-aware formatter.
    static func format(_ move: Move, in position: Position) -> String {
        _ = position
        return SANParser.convert(move: move)
    }
}
