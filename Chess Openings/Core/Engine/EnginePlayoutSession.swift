import Foundation
import ChessKit
import Observation

@Observable
@MainActor
final class EnginePlayoutSession {
    let userSide: Side
    let level: EngineLevel
    private let engine: EngineServicing

    private(set) var position: Position
    private(set) var history: [Move]
    private(set) var historyByUser: [Bool]
    private(set) var preMovePositions: [Position]
    private(set) var status: PlayoutStatus
    /// Last evaluation reported by the engine, from the engine's pov
    /// (positive = engine winning). `nil` until the engine has run.
    private(set) var lastEngineEval: EngineEvaluation?

    /// Read-only snapshot of the underlying board's state. Used by
    /// the termination helper.
    var boardState: Board.State { board.state }

    /// Same contract as `DrillSession.onMoveApplied` so the existing
    /// audio plumbing works unchanged.
    var onMoveApplied: ((Move, Position, Position, Bool) -> Void)?

    private var board: Board

    init(
        startingPosition: Position,
        userSide: Side,
        level: EngineLevel,
        engine: EngineServicing
    ) {
        self.userSide = userSide
        self.level = level
        self.engine = engine
        self.board = Board(position: startingPosition)
        self.position = startingPosition
        self.history = []
        self.historyByUser = []
        self.preMovePositions = []
        self.lastEngineEval = nil

        let sideToMoveIsUser: Bool = {
            switch (userSide, startingPosition.sideToMove) {
            case (.white, .white), (.black, .black): return true
            default:                                  return false
            }
        }()
        self.status = sideToMoveIsUser ? .waitingForUser : .engineThinking
    }

    /// Drives the initial engine-first move if the position starts on
    /// the engine's turn. Call once from the view after init. The
    /// constructor doesn't kick off async work so the view decides
    /// when (e.g. after a brief delay so the user can orient).
    func bootstrap() async {
        guard status == .engineThinking else { return }
        await playEngineReply()
    }

    /// User submits a move. Validates legality via chesskit, applies
    /// it, checks for rules-based termination, and either ends the
    /// game or asks the engine to reply. No-ops if it isn't currently
    /// the user's turn or if the move is illegal in the current
    /// position.
    func submit(_ move: Move) async {
        guard status == .waitingForUser else { return }
        guard board.canMove(pieceAt: move.start, to: move.end) else {
            return
        }
        recordApply(move, byUser: true)
        // FIXME: promotion handling deferred to post-v1 — if the user
        // submitted a promotion-shaped move, board.state will report
        // .promotion(...) and reason(forBoardState:) returns nil. For
        // v1, parseUCI rejects engine promotion moves; user-side
        // promotion UX lands later.
        if let reason = Self.reason(forBoardState: board.state) {
            status = .gameOver(reason)
            return
        }
        // v1: user must commit the promotion choice via the existing
        // promotion picker; don't hand to the engine until that's
        // resolved.
        if case .promotion = board.state { return }
        await playEngineReply()
    }

    private func playEngineReply() async {
        // called from submit() while .waitingForUser; defensive on
        // bootstrap entry where status is already .engineThinking.
        status = .engineThinking
        let move = await engine.bestMove(
            at: position,
            skill: level.stockfishSkill,
            budget: level.opponentSearchBudget
        )
        guard let move,
              let parsed = parseUCI(move.uci, in: position) else {
            status = .waitingForUser
            return
        }
        recordApply(parsed, byUser: false)
        if let reason = Self.reason(forBoardState: board.state) {
            status = .gameOver(reason)
            return
        }
        status = .waitingForUser
    }

    private func apply(_ move: Move, byUser: Bool) {
        let pre = position
        board.move(pieceAt: move.start, to: move.end)
        position = board.position
        onMoveApplied?(move, pre, position, byUser)
    }

    private func recordApply(_ move: Move, byUser: Bool) {
        preMovePositions.append(position)
        apply(move, byUser: byUser)
        history.append(move)
        historyByUser.append(byUser)
    }

    /// Bridge a UCI long-algebraic move ("e2e4") to a ChessKit `Move`
    /// legal in `position`. Promotion strings (5-char like "e7e8q")
    /// are rejected here.
    // FIXME: promotion handling deferred to post-v1
    private func parseUCI(_ uci: String, in pos: Position) -> Move? {
        guard uci.count == 4 else { return nil }
        let fromStr = String(uci.prefix(2))
        let toStr = String(uci.dropFirst(2).prefix(2))
        guard Self.isAlgebraicSquare(fromStr),
              Self.isAlgebraicSquare(toStr) else { return nil }
        let from = Square(fromStr)
        let to = Square(toStr)
        guard let piece = pos.piece(at: from) else { return nil }
        return Move(result: .move, piece: piece, start: from, end: to)
    }

    /// chesskit's `Square(_:)` initialiser is non-failable and silently
    /// snaps malformed notation to `.a1`, so we pre-validate here:
    /// expect two characters, file in a-h, rank in 1-8.
    private static func isAlgebraicSquare(_ s: String) -> Bool {
        guard s.count == 2 else { return false }
        let file = s.first!
        let rank = s.last!
        return ("a"..."h").contains(file) && ("1"..."8").contains(rank)
    }
}
