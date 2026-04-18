import Foundation
import SwiftData

@Model
final class LineProgress {
    var line: Line?
    var correctStreak: Int
    var isLearned: Bool
    var timesAttempted: Int
    var timesCompleted: Int
    var lastAttemptedAt: Date?
    var mistakesData: Data                    // JSON-encoded [Mistake] (rolling last 20)

    var mistakes: [Mistake] {
        get { (try? JSONDecoder().decode([Mistake].self, from: mistakesData)) ?? [] }
        set {
            let capped = Array(newValue.suffix(20))
            mistakesData = (try? JSONEncoder().encode(capped)) ?? Data()
        }
    }

    init() {
        self.correctStreak = 0
        self.isLearned = false
        self.timesAttempted = 0
        self.timesCompleted = 0
        self.lastAttemptedAt = nil
        self.mistakesData = Data()
    }
}
