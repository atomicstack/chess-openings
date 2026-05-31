import Foundation
import SwiftData

@Model
final class UserSettings {
    var drillModeRaw: String
    var masteryThreshold: Int
    var soundsEnabled: Bool = true
    var seededVersion: Int = 0
    var engineLevel: Int = 10
    var moveAnalysisDepth: Int = 10
    var moveQualityBadgeMs: Int = 1500

    var drillMode: DrillMode {
        get { DrillMode(rawValue: drillModeRaw) ?? .strict }
        set { drillModeRaw = newValue.rawValue }
    }

    init(
        drillMode: DrillMode = .strict,
        masteryThreshold: Int = 3,
        soundsEnabled: Bool = true,
        seededVersion: Int = 0,
        engineLevel: Int = 10,
        moveAnalysisDepth: Int = 10,
        moveQualityBadgeMs: Int = 1500
    ) {
        self.drillModeRaw = drillMode.rawValue
        self.masteryThreshold = masteryThreshold
        self.soundsEnabled = soundsEnabled
        self.seededVersion = seededVersion
        self.engineLevel = max(0, min(20, engineLevel))
        self.moveAnalysisDepth = max(6, min(20, moveAnalysisDepth))
        self.moveQualityBadgeMs = max(500, min(5000, moveQualityBadgeMs))
    }
}
