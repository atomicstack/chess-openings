import Foundation
import ChessKit

/// A move returned by the engine, normalised to UCI long algebraic
/// (e.g. "e2e4", "e7e8q").
struct EngineMove: Equatable, Sendable {
    let uci: String
}

/// Engine score from the engine's point of view. `.cp` is centipawns;
/// `.mate(in:)` is the count of *moves* (not plies) to mate, negative
/// when the engine is the one getting mated.
enum EngineEvaluation: Equatable, Sendable {
    case cp(Int)
    case mate(in: Int)
}

/// Protocol-fronted engine api so tests can inject a deterministic
/// fake without booting a real stockfish.
protocol EngineServicing: AnyObject {
    func bestMove(
        at position: Position,
        skill: Int,
        budget: SearchBudget
    ) async -> EngineMove?

    func evaluate(
        at position: Position,
        budget: SearchBudget
    ) async -> EngineEvaluation
}
