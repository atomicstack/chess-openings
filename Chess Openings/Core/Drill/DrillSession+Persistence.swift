import Foundation
import SwiftData

extension DrillSession {
    /// Hook a `DrillSession`'s observation callbacks into SwiftData so
    /// `line.mastery` is updated and persisted every time the user
    /// finishes a line or plays an off-book move. Composes with any
    /// callbacks already attached (e.g. audio); pre-existing closures
    /// are invoked after the persistence step.
    @MainActor
    func attachProgressTracking(
        line: Line,
        threshold: Int,
        context: ModelContext,
        service: ProgressService = ProgressService()
    ) {
        let priorComplete = onLineComplete
        onLineComplete = { [weak self] in
            guard let self else { priorComplete?(); return }
            service.recordCompletion(
                line: line,
                madeMistake: !self.completedWithoutMistake,
                threshold: threshold
            )
            Self.ensureInContext(line.mastery, context: context)
            try? context.save()
            priorComplete?()
        }

        let priorIncorrect = onIncorrectMove
        onIncorrectMove = { bookPly, playedSan in
            service.recordMistake(line: line, ply: bookPly, playedSan: playedSan)
            Self.ensureInContext(line.mastery, context: context)
            try? context.save()
            priorIncorrect?(bookPly, playedSan)
        }
    }

    /// Newly-allocated `LineProgress` instances created by
    /// `ProgressService` aren't registered with the parent's model
    /// context automatically. Inserting them is a no-op once they're
    /// already managed, so this is safe to call on every event.
    private static func ensureInContext(_ progress: LineProgress?, context: ModelContext) {
        guard let progress, progress.modelContext == nil else { return }
        context.insert(progress)
    }
}
