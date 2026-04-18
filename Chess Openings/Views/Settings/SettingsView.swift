import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]

    var body: some View {
        NavigationStack {
            Form {
                Section("drill mode") {
                    Picker("", selection: bindingMode()) {
                        Text("strict").tag(DrillMode.strict)
                        Text("show-and-retry").tag(DrillMode.showAndRetry)
                    }.pickerStyle(.inline)
                }
                Section("mastery") {
                    Stepper("correct streak: \(currentThreshold())",
                            value: bindingThreshold(), in: 1...10)
                }
                Section("sound") {
                    Toggle("move + feedback sounds", isOn: bindingSounds())
                }
                Section("data") {
                    Button("reset all progress", role: .destructive) { resetProgress() }
                }
            }
            .navigationTitle("settings")
            .toolbar { Button("done") { dismiss() } }
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
