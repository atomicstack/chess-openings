import Foundation

struct ProgressService {
    func recordCompletion(line: Line, madeMistake: Bool, threshold: Int) {
        let progress = line.mastery ?? LineProgress()
        if madeMistake {
            progress.correctStreak = 0
            progress.isLearned = false
        } else {
            progress.correctStreak += 1
            if progress.correctStreak >= threshold { progress.isLearned = true }
        }
        progress.timesAttempted += 1
        progress.timesCompleted += 1
        progress.lastAttemptedAt = Date()
        line.mastery = progress
    }

    func recordMistake(line: Line, ply: BookPly, playedSan: String) {
        let progress = line.mastery ?? LineProgress()
        var m = progress.mistakes
        m.append(Mistake(ply: ply, playedSan: playedSan, at: Date()))
        progress.mistakes = m
        line.mastery = progress
    }
}
