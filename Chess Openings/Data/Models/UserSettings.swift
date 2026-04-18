import Foundation
import SwiftData

@Model
final class UserSettings {
    var drillModeRaw: String
    var masteryThreshold: Int
    var soundsEnabled: Bool = true

    var drillMode: DrillMode {
        get { DrillMode(rawValue: drillModeRaw) ?? .strict }
        set { drillModeRaw = newValue.rawValue }
    }

    init(
        drillMode: DrillMode = .strict,
        masteryThreshold: Int = 3,
        soundsEnabled: Bool = true
    ) {
        self.drillModeRaw = drillMode.rawValue
        self.masteryThreshold = masteryThreshold
        self.soundsEnabled = soundsEnabled
    }
}
