import Foundation
import ChessKit
import Observation

struct LineSnapshot: Sendable {
    let plies: [BookPly]
}

@Observable
@MainActor
final class DrillSession {
    let line: LineSnapshot
    let oracle: MoveOracle
    var mode: DrillMode
    let masteryThreshold: Int

    /// Delay in milliseconds inserted between the user's move and the
    /// session's scripted reply, so the board animation from the user
    /// move can resolve before the reply begins. Defaults to 0 so tests
    /// stay fast; the UI sets a human-friendly delay.
    var scriptedReplyDelayMs: Int = 0

    /// Fires after every move applied to the board — user moves,
    /// scripted replies, and black-side autoplay openings. Consumers
    /// (e.g. the audio layer) get the move plus pre/post positions and
    /// a `byUser` flag so they can classify the event in context.
    var onMoveApplied: ((Move, Position, Position, Bool) -> Void)?

    private(set) var position: Position
    private(set) var history: [Move]
    private(set) var preMovePositions: [Position]
    /// Parallel to `history`: `true` for moves the user submitted, `false`
    /// for scripted replies and black-side autoplay. `undo` uses this to
    /// step back to the last position the user was prompted from, never
    /// past an autoplay-only state.
    private(set) var historyByUser: [Bool]
    private(set) var status: DrillStatus
    private(set) var correctStreak: Int
    private(set) var completedWithoutMistake: Bool

    /// Position immediately before the most recent applied move, or `nil`
    /// if no move has been applied yet. Exposed so downstream consumers
    /// (e.g. the audio layer) can classify the last move in context.
    var lastPreMovePosition: Position? { preMovePositions.last }

    /// The most recent move applied to the board (either the user's
    /// move or the scripted reply, whichever was last), or `nil` if
    /// no move has been played yet.
    var lastAppliedMove: Move? { history.last }

    /// chesskit's `Board` is the stateful wrapper that knows how to
    /// apply a move and update `position`. we keep one here and
    /// mirror its `position` on `self` after each mutation.
    private var board: Board

    init(
        line: LineSnapshot,
        oracle: MoveOracle,
        mode: DrillMode,
        masteryThreshold: Int,
        initialStreak: Int = 0
    ) {
        self.line = line
        self.oracle = oracle
        self.mode = mode
        self.masteryThreshold = masteryThreshold
        self.board = Board(position: .standard)
        self.position = .standard
        self.history = []
        self.preMovePositions = []
        self.historyByUser = []
        self.status = .waitingForUser
        self.correctStreak = initialStreak
        self.completedWithoutMistake = true
    }

    func submit(_ move: Move) async {
        // allow recovery from a prior mistake (show-and-retry)
        if case .mistake = status { status = .waitingForUser }
        status = .evaluating

        let candidates = await oracle.acceptableMoves(at: position, history: history)
        guard let match = candidates.first(where: { Self.sameChessMove($0.move, move) }) else {
            // off-book
            completedWithoutMistake = false
            correctStreak = 0
            switch mode {
            case .strict:
                // ui snaps piece back; no state change
                status = .waitingForUser
            case .showAndRetry:
                if let first = candidates.first {
                    status = .mistake(book: first, played: move)
                } else {
                    status = .waitingForUser
                }
            }
            return
        }

        // match — apply user move via Board
        recordApply(match.move, byUser: true)

        // apply scripted reply if there is one, after a brief pause so
        // the user's piece animation can finish before the reply starts
        if history.count < line.plies.count {
            let replyPly = line.plies[history.count]
            if let replyMove = SANParser.parse(move: replyPly.san, in: position) {
                if scriptedReplyDelayMs > 0 {
                    try? await Task.sleep(for: .milliseconds(scriptedReplyDelayMs))
                }
                recordApply(replyMove, byUser: false)
            }
        }

        if history.count >= line.plies.count {
            status = .lineComplete
            if completedWithoutMistake { correctStreak += 1 }
        } else {
            status = .waitingForUser
        }
    }

    private func apply(_ move: Move, byUser: Bool) {
        let pre = position
        board.move(pieceAt: move.start, to: move.end)
        position = board.position
        onMoveApplied?(move, pre, position, byUser)
    }

    /// Apply a move and record it in `history`/`preMovePositions`/`historyByUser`
    /// so the three arrays stay the same length. Callers must not append to
    /// `history` directly — go through this helper.
    private func recordApply(_ move: Move, byUser: Bool) {
        preMovePositions.append(position)
        apply(move, byUser: byUser)
        history.append(move)
        historyByUser.append(byUser)
    }

    /// Same-chess-move identity: compares only the essential fields that
    /// define the move semantically. Full `Move ==` is too strict because
    /// moves produced by `Board.move(pieceAt:to:)` carry different
    /// metadata (e.g. `.capture(piece)` with a piece-square payload,
    /// disambiguation, check state) than moves produced by
    /// `SANParser.parse(...)`, so a legitimate capture played via the
    /// board won't satisfy `==` against the oracle's parsed candidate.
    static func sameChessMove(_ a: Move, _ b: Move) -> Bool {
        return a.start == b.start
            && a.end == b.end
            && a.promotedPiece?.kind == b.promotedPiece?.kind
    }

    /// Apply the next scripted book ply without validating against the
    /// user. Used to auto-play the opening move when the user is playing
    /// black, so the drill board is already waiting on the user's reply.
    /// No-op if the line is exhausted or the next ply cannot be parsed.
    func autoplayNextBookPly() {
        guard history.count < line.plies.count else { return }
        let ply = line.plies[history.count]
        guard let move = SANParser.parse(move: ply.san, in: position) else { return }
        recordApply(move, byUser: false)
        if history.count >= line.plies.count {
            status = .lineComplete
            if completedWithoutMistake { correctStreak += 1 }
        } else {
            status = .waitingForUser
        }
    }

    /// Step back to the position the user was last prompted from. Pops
    /// the most recent user move and the scripted reply that followed it
    /// (if any). No-op when the only moves on the board are non-user
    /// (e.g. the black-side autoplay fired but the user hasn't moved yet)
    /// — popping past that state would silently flip which side the user
    /// controls.
    func undo() {
        guard let lastUserIdx = historyByUser.lastIndex(of: true) else { return }
        let popCount = history.count - lastUserIdx
        history.removeLast(popCount)
        preMovePositions.removeLast(min(popCount, preMovePositions.count))
        historyByUser.removeLast(popCount)
        rebuildBoardFromHistory()
        status = .waitingForUser
    }

    /// Return to the initial position and clear all drill state.
    func reset() {
        history = []
        preMovePositions = []
        historyByUser = []
        board = Board(position: .standard)
        position = board.position
        status = .waitingForUser
        completedWithoutMistake = true
    }

    /// chesskit's `Board` does not support undo, so we rebuild it
    /// by replaying `history` from the standard starting position.
    private func rebuildBoardFromHistory() {
        var replay = Board(position: .standard)
        for move in history {
            replay.move(pieceAt: move.start, to: move.end)
        }
        board = replay
        position = board.position
    }
}
