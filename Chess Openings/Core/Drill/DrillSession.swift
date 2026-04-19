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

    /// Fires the instant `status` transitions to `.lineComplete`.
    /// Consumers use this to trigger one-shot end-of-line effects
    /// (victory sound, celebration animation) that shouldn't be
    /// re-fired by later observable updates.
    var onLineComplete: (() -> Void)?

    /// Fires when the user submits a move that isn't in the book.
    /// Independent of the resulting `DrillStatus` — both strict and
    /// show-and-retry modes fire this.
    var onIncorrectMove: (() -> Void)?

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

    /// Total seconds the user has been actively on the clock for this
    /// line — summed over every wall-clock interval where the board was
    /// waiting on the user (status `.waitingForUser` or `.mistake`).
    /// Scripted reply delays and black-side autoplay time are excluded.
    private(set) var userThinkingTime: TimeInterval = 0

    /// Wall-clock instant the current "it's your turn" interval began,
    /// or `nil` while the session is mid-computer-action (scripted
    /// reply in flight, line complete). The next `submit(_:)` accumulates
    /// `now - lastPromptAt` into `userThinkingTime` before clearing it.
    private var lastPromptAt: Date?

    /// Average seconds-per-ply for the just-completed line, or `nil`
    /// if the line isn't complete. Uses `userThinkingTime` (computer
    /// time excluded) divided by total plies in the line, so black-side
    /// drills are judged on the same scale as white-side drills.
    var averageSecondsPerPly: Double? {
        guard case .lineComplete = status, !line.plies.isEmpty else { return nil }
        return userThinkingTime / Double(line.plies.count)
    }

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
        // user is on the clock the moment the session shows the board.
        // for black-side drills, autoplayNextBookPly re-stamps (discarding
        // this pre-autoplay interval) so only real user time accumulates.
        self.lastPromptAt = Date()
    }

    func submit(_ move: Move) async {
        // close the current "your turn" interval — the user just acted.
        // clear the stamp so the scripted-reply sleep below isn't counted.
        accumulateUserThinking()

        // allow recovery from a prior mistake (show-and-retry)
        if case .mistake = status { status = .waitingForUser }
        status = .evaluating

        let candidates = await oracle.acceptableMoves(at: position, history: history)
        guard let match = candidates.first(where: { Self.sameChessMove($0.move, move) }) else {
            // off-book
            completedWithoutMistake = false
            correctStreak = 0
            onIncorrectMove?()
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
            // user stays on the clock for the retry
            lastPromptAt = Date()
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
            finishLine()
        } else {
            status = .waitingForUser
            lastPromptAt = Date()
        }
    }

    /// Add the elapsed time since `lastPromptAt` to `userThinkingTime`
    /// and clear the stamp. No-op if the stamp isn't set (e.g. the
    /// session is mid-scripted-action). Call before the "it's your turn"
    /// interval closes.
    private func accumulateUserThinking() {
        guard let stamp = lastPromptAt else { return }
        userThinkingTime += Date().timeIntervalSince(stamp)
        lastPromptAt = nil
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
            finishLine()
        } else {
            status = .waitingForUser
            // the user is now on the clock; discard any pre-autoplay
            // interval (e.g. the 750ms wait the UI uses before firing
            // black-side autoplay) by re-stamping rather than accumulating.
            lastPromptAt = Date()
        }
    }

    /// Shared transition into `.lineComplete`. Stops the user-thinking
    /// clock, bumps the streak on a clean run, fires the one-shot
    /// callback, and sets the status. Callers must have already applied
    /// the final move before invoking.
    private func finishLine() {
        lastPromptAt = nil
        status = .lineComplete
        if completedWithoutMistake { correctStreak += 1 }
        onLineComplete?()
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
        lastPromptAt = Date()
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
        userThinkingTime = 0
        lastPromptAt = Date()
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
