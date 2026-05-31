import Foundation

/// User-facing engine strength, wraps stockfish's `Skill Level`
/// option (0…20) and the matching opponent search budget.
struct EngineLevel: Equatable, Sendable {
    let stockfishSkill: Int

    init(rawSkill: Int) {
        self.stockfishSkill = max(0, min(20, rawSkill))
    }

    static let `default` = EngineLevel(rawSkill: 10)

    var opponentSearchBudget: SearchBudget {
        let d = 4 + (stockfishSkill * 11) / 20
        return .depth(d)
    }
}
