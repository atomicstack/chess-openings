import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]
    @State private var showResetConfirm: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("drill mode") {
                    Picker("drill mode", selection: bindingMode()) {
                        Text("strict").tag(DrillMode.strict)
                        Text("show-and-retry").tag(DrillMode.showAndRetry)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section("mastery") {
                    Stepper("correct streak: \(currentThreshold())",
                            value: bindingThreshold(), in: 1...10)
                }
                Section("sound") {
                    Toggle("move + feedback sounds", isOn: bindingSounds())
                }
                Section("engine") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("difficulty: \(currentEngineLevel())")
                            .font(.callout)
                        Slider(
                            value: bindingEngineLevel(),
                            in: 0...20,
                            step: 1
                        )
                        Text("0 = very weak, 20 = full strength")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("move quality") {
                    Stepper(
                        "analysis depth: \(currentMoveAnalysisDepth())",
                        value: bindingMoveAnalysisDepth(),
                        in: 6...20
                    )
                    Stepper(
                        "badge duration: \(currentMoveQualityBadgeMs()) ms",
                        value: bindingMoveQualityBadgeMs(),
                        in: 500...5000,
                        step: 100
                    )
                    Text("how deep stockfish searches when grading your moves, and how long the move-quality badge stays on the board.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section("data") {
                    Button("reset all progress", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
            .navigationTitle("settings")
            .toolbar { Button("done") { dismiss() } }
            .confirmationDialog(
                "reset all progress?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("reset everything", role: .destructive) { resetProgress() }
                Button("cancel", role: .cancel) { }
            } message: {
                Text("this wipes every line's streak, learned flag, completion count, and mistake log. there is no undo.")
            }
        }
        .task { ensureSettingsExist() }
    }

    private func ensureSettingsExist() {
        if settings.isEmpty { context.insert(UserSettings()); try? context.save() }
    }
    private func current() -> UserSettings { settings.first ?? UserSettings() }
    private func currentThreshold() -> Int { current().masteryThreshold }
    private func bindingMode() -> Binding<DrillMode> {
        Binding(get: { self.current().drillMode },
                set: { self.current().drillMode = $0; try? context.save() })
    }
    private func bindingThreshold() -> Binding<Int> {
        Binding(get: { self.current().masteryThreshold },
                set: { self.current().masteryThreshold = $0; try? context.save() })
    }
    private func bindingSounds() -> Binding<Bool> {
        Binding(get: { self.current().soundsEnabled },
                set: { self.current().soundsEnabled = $0; try? context.save() })
    }
    private func currentEngineLevel() -> Int { current().engineLevel }

    private func bindingEngineLevel() -> Binding<Double> {
        Binding(
            get: { Double(self.current().engineLevel) },
            set: {
                self.current().engineLevel = max(0, min(20, Int($0.rounded())))
                try? context.save()
            }
        )
    }

    private func currentMoveAnalysisDepth() -> Int { current().moveAnalysisDepth }
    private func currentMoveQualityBadgeMs() -> Int { current().moveQualityBadgeMs }

    private func bindingMoveAnalysisDepth() -> Binding<Int> {
        Binding(
            get: { self.current().moveAnalysisDepth },
            set: {
                self.current().moveAnalysisDepth = max(6, min(20, $0))
                try? context.save()
            }
        )
    }

    private func bindingMoveQualityBadgeMs() -> Binding<Int> {
        Binding(
            get: { self.current().moveQualityBadgeMs },
            set: {
                self.current().moveQualityBadgeMs = max(500, min(5000, $0))
                try? context.save()
            }
        )
    }
    private func resetProgress() {
        do {
            let progresses = try context.fetch(FetchDescriptor<LineProgress>())
            for p in progresses {
                p.correctStreak = 0
                p.isLearned = false
                p.timesCompleted = 0
                p.mistakes = []
            }
            try context.save()
        } catch { print("reset failed: \(error)") }
    }
}
