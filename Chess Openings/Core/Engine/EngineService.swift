import Foundation
import ChessKit
import ChessKitEngine

/// Real, chesskit-engine-backed implementation of `EngineServicing`.
/// Owns one `Engine` instance for the service's lifetime; `Skill
/// Level` is swapped via `setoption` per query so opponent moves
/// follow the user's chosen difficulty while hint / evaluate calls
/// run at full strength.
@MainActor
final class EngineService: EngineServicing {
    private let engine: Engine
    private var didInitialSetup = false

    init() {
        self.engine = Engine(type: .stockfish)
    }

    func bestMove(
        at position: Position,
        skill: Int,
        budget: SearchBudget
    ) async -> EngineMove? {
        await ensureReady()
        await setSkill(skill)
        await engine.send(command: .position(.fen(position.fen)))
        let result = await runUntilBestmove(budget: budget)
        return result.move
    }

    func evaluate(
        at position: Position,
        budget: SearchBudget
    ) async -> EngineEvaluation {
        await ensureReady()
        await setSkill(20)
        await engine.send(command: .position(.fen(position.fen)))
        let result = await runUntilBestmove(budget: budget)
        return result.score ?? .cp(0)
    }

    /// Cleanly stops the engine. Call when the playout ends so we
    /// don't leak the underlying process across drill sessions.
    func shutdown() async {
        await engine.stop()
        didInitialSetup = false
    }

    // MARK: - private

    private func ensureReady() async {
        guard !didInitialSetup else { return }
        await engine.start()
        // wait for the engine to publish readyok / uciok before sending
        // nnue paths. consume() drains until the predicate matches.
        await consume(until: { response in
            if case .readyok = response { return true }
            return false
        })
        if let mainPath = Self.bundledNNUEPath(name: "nn-1111cefa1111") {
            await engine.send(command: .setoption(id: "EvalFile",
                                                  value: mainPath))
        }
        if let smallPath = Self.bundledNNUEPath(name: "nn-37f18f62d772") {
            await engine.send(command: .setoption(id: "EvalFileSmall",
                                                  value: smallPath))
        }
        await engine.send(command: .isready)
        await consume(until: { response in
            if case .readyok = response { return true }
            return false
        })
        didInitialSetup = true
    }

    private func setSkill(_ raw: Int) async {
        let clamped = max(0, min(20, raw))
        await engine.send(command: .setoption(id: "Skill Level",
                                              value: String(clamped)))
    }

    private struct BestmoveResult {
        let move: EngineMove?
        let score: EngineEvaluation?
    }

    private func runUntilBestmove(budget: SearchBudget) async -> BestmoveResult {
        switch budget {
        case .depth(let d):
            await engine.send(command: .go(depth: d))
        case .movetimeMs(let ms):
            await engine.send(command: .go(movetime: ms))
        }
        guard let stream = await engine.responseStream else {
            return BestmoveResult(move: nil, score: nil)
        }
        var latestScore: EngineEvaluation? = nil
        for await response in stream {
            switch response {
            case .info(let info):
                if let s = info.score {
                    if let m = s.mate {
                        latestScore = .mate(in: m)
                    } else if let cp = s.cp {
                        latestScore = .cp(Int(cp.rounded()))
                    }
                }
            case .bestmove(let uci, _):
                guard !uci.isEmpty, uci != "(none)" else {
                    return BestmoveResult(move: nil, score: latestScore)
                }
                return BestmoveResult(
                    move: EngineMove(uci: uci),
                    score: latestScore
                )
            default:
                continue
            }
        }
        return BestmoveResult(move: nil, score: latestScore)
    }

    private func consume(
        until match: @escaping (EngineResponse) -> Bool
    ) async {
        guard let stream = await engine.responseStream else { return }
        for await r in stream where match(r) { return }
    }

    private static func bundledNNUEPath(name: String) -> String? {
        Bundle.main.path(forResource: name, ofType: "nnue")
    }
}
