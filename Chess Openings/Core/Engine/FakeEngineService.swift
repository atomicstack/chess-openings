import Foundation
import ChessKit

/// Deterministic test double for `EngineServicing`. Pops moves and
/// evaluations from scripted arrays in order. When the corresponding
/// script runs out, `bestMove` returns `nil` and `evaluate` returns
/// `.cp(0)` so tests fail loudly if they outpace their script.
@MainActor
final class FakeEngineService: EngineServicing {
    var scriptedBestMoves: [String] = []
    var scriptedEvaluations: [EngineEvaluation] = []

    private(set) var bestMoveCalls = 0
    private(set) var evaluateCalls = 0
    private(set) var lastBestMoveSkill: Int?

    func bestMove(
        at position: Position,
        skill: Int,
        budget: SearchBudget
    ) async -> EngineDecision? {
        bestMoveCalls += 1
        lastBestMoveSkill = skill
        guard !scriptedBestMoves.isEmpty else { return nil }
        let move = EngineMove(uci: scriptedBestMoves.removeFirst())
        let eval = scriptedEvaluations.isEmpty
            ? nil
            : scriptedEvaluations.removeFirst()
        return EngineDecision(move: move, evaluation: eval)
    }

    func evaluate(
        at position: Position,
        budget: SearchBudget
    ) async -> EngineEvaluation {
        evaluateCalls += 1
        guard !scriptedEvaluations.isEmpty else { return .cp(0) }
        return scriptedEvaluations.removeFirst()
    }
}
