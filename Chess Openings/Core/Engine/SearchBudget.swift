import Foundation

/// Bound on how long stockfish should think for a single query.
/// Maps to either a `go depth N` or `go movetime M` UCI command.
enum SearchBudget: Equatable, Sendable {
    case depth(Int)
    case movetimeMs(Int)
}
