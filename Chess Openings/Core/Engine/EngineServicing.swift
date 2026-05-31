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

/// Pair of move + evaluation returned by `bestMove`. The evaluation
/// is the engine's view of the position at the moment it committed to
/// `move`, from the engine's pov (positive = engine winning). `nil`
/// when no `info score` line was seen before bestmove.
struct EngineDecision: Equatable, Sendable {
    let move: EngineMove
    let evaluation: EngineEvaluation?
}

/// Protocol-fronted engine api so tests can inject a deterministic
/// fake without booting a real stockfish.
protocol EngineServicing: AnyObject {
    func bestMove(
        at position: Position,
        skill: Int,
        budget: SearchBudget
    ) async -> EngineDecision?

    func evaluate(
        at position: Position,
        budget: SearchBudget
    ) async -> EngineEvaluation
}
