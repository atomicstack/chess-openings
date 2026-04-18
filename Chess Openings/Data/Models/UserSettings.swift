import Foundation
import SwiftData

@Model
final class UserSettings {
    var drillModeRaw: String
    var masteryThreshold: Int

    var drillMode: DrillMode {
        get { DrillMode(rawValue: drillModeRaw) ?? .strict }
        set { drillModeRaw = newValue.rawValue }
    }

    init(drillMode: DrillMode = .strict, masteryThreshold: Int = 3) {
        self.drillModeRaw = drillMode.rawValue
        self.masteryThreshold = masteryThreshold
    }
}
