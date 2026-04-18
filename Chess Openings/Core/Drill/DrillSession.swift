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

    private(set) var position: Position
    private(set) var history: [Move]
    private(set) var preMovePositions: [Position]
    private(set) var status: DrillStatus
    private(set) var correctStreak: Int
    private(set) var completedWithoutMistake: Bool

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
        self.status = .waitingForUser
        self.correctStreak = initialStreak
        self.completedWithoutMistake = true
    }

    func submit(_ move: Move) async {
        // allow recovery from a prior mistake (show-and-retry)
        if case .mistake = status { status = .waitingForUser }
        status = .evaluating

        let candidates = await oracle.acceptableMoves(at: position, history: history)
        guard let match = candidates.first(where: { $0.move == move }) else {
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
        preMovePositions.append(position)
        apply(match.move)
        history.append(match.move)

        // apply scripted reply if there is one
        if history.count < line.plies.count {
            let replyPly = line.plies[history.count]
            if let replyMove = SANParser.parse(move: replyPly.san, in: position) {
                preMovePositions.append(position)
                apply(replyMove)
                history.append(replyMove)
            }
        }

        if history.count >= line.plies.count {
            status = .lineComplete
            if completedWithoutMistake { correctStreak += 1 }
        } else {
            status = .waitingForUser
        }
    }

    private func apply(_ move: Move) {
        board.move(pieceAt: move.start, to: move.end)
        position = board.position
    }

    /// Step back one full move (user move + scripted reply) so the user
    /// can retry the same prompt. If the history contains only a single
    /// ply (i.e. the scripted reply didn't happen), that ply is removed.
    func undo() {
        guard !history.isEmpty else { return }
        let stepsBack = min(2, history.count)
        history.removeLast(stepsBack)
        let preCount = min(stepsBack, preMovePositions.count)
        preMovePositions.removeLast(preCount)
        rebuildBoardFromHistory()
        status = .waitingForUser
    }

    /// Return to the initial position and clear all drill state.
    func reset() {
        history = []
        preMovePositions = []
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
