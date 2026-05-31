import Foundation
import ChessKit

struct MoveAnnotation: Equatable {
    /// Destination square of the move being annotated.
    let square: Square
    let quality: MoveQuality
    /// A fresh `id` (typically `Date()`) restarts the badge animation
    /// when assigned. Two annotations with the same `square + quality`
    /// but different ids are treated as distinct events.
    let id: Date
}
