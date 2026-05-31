import Foundation
import ChessKit
import ChessKitEngine

/// Real, chesskit-engine-backed implementation of `EngineServicing`.
/// Owns one `Engine` instance for the service's lifetime; `Skill
/// Level` is swapped via `setoption` per query so opponent moves
/// follow the user's chosen difficulty while hint / evaluate calls
/// run at full strength.
///
/// Engine-touching work is funnelled through `enqueue` so the shared
/// `responseStream` is only ever consumed by one task at a time. This
/// prevents two concurrent `bestMove` / `evaluate` calls from racing
/// for the same `.bestmove` event, and stops stale `info` frames from
/// a previous query leaking into the next consumer.
@MainActor
final class EngineService: EngineServicing {
    private let engine: Engine

    /// Tail of the serialised work chain. Each call awaits the prior
    /// chain element before touching the engine, so only one query is
    /// in flight at a time.
    private var inflight: Task<Void, Never>?

    /// Cached one-shot setup task. First caller starts it; concurrent
    /// callers await the same task instead of racing to start the
    /// engine twice.
    private var setupTask: Task<Void, Never>?

    init() {
        self.engine = Engine(type: .stockfish)
    }

    func bestMove(
        at position: Position,
        skill: Int,
        budget: SearchBudget
    ) async -> EngineDecision? {
        await enqueue {
            await self.ensureReady()
            await self.setSkill(skill)
            await self.engine.send(command: .position(.fen(position.fen)))
            let result = await self.runUntilBestmove(budget: budget)
            guard let m = result.move else { return nil }
            return EngineDecision(move: m, evaluation: result.score)
        }
    }

    func evaluate(
        at position: Position,
        budget: SearchBudget
    ) async -> EngineEvaluation {
        await enqueue {
            await self.ensureReady()
            await self.setSkill(20)
            await self.engine.send(command: .position(.fen(position.fen)))
            let result = await self.runUntilBestmove(budget: budget)
            return result.score ?? .cp(0)
        }
    }

    /// Cleanly stops the engine. Call when the playout ends so we
    /// don't leak the underlying process across drill sessions.
    func shutdown() async {
        await inflight?.value
        await engine.stop()
        inflight = nil
        setupTask = nil
    }

    // MARK: - private

    /// Serialises engine-touching work. Each call waits for the prior
    /// chain element to finish before running, and parks the next
    /// caller behind itself. The returned value comes from `work`; the
    /// chain itself only tracks completion (`Task<Void, Never>`).
    @discardableResult
    private func enqueue<T: Sendable>(
        _ work: @MainActor @Sendable @escaping () async -> T
    ) async -> T {
        let previous = inflight
        let task = Task<T, Never> {
            await previous?.value
            return await work()
        }
        inflight = Task { _ = await task.value }
        return await task.value
    }

    private func ensureReady() async {
        if let t = setupTask {
            await t.value
            return
        }
        let t = Task<Void, Never> { [self] in
            await runInitialSetup()
        }
        setupTask = t
        await t.value
    }

    private func runInitialSetup() async {
        await engine.start()
        // wait for the engine to publish readyok / uciok before sending
        // nnue paths. consume() drains until the predicate matches.
        await consume(until: { response in
            if case .readyok = response { return true }
            return false
        })
        // nnue filenames are sourced from stockfish's NN-tests catalogue
        // (https://tests.stockfishchess.org/nns) — bump these constants
        // when fetching a newer net revision.
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
        var latestScore: EngineEvaluation?
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
        until match: (EngineResponse) -> Bool
    ) async {
        guard let stream = await engine.responseStream else { return }
        for await r in stream where match(r) { return }
    }

    private static func bundledNNUEPath(name: String) -> String? {
        Bundle.main.path(forResource: name, ofType: "nnue")
    }
}
