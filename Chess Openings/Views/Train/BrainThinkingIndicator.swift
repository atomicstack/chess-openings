import SwiftUI
import Combine

/// Pure decision: should the brain be visible right now? Tested via
/// the unit tests so SwiftUI rendering isn't on the critical path.
struct BrainVisibility {
    let isThinking: Bool
    let startedAt: Date?
    let now: Date
    let pulsePeriod: TimeInterval

    var shouldBeVisible: Bool {
        if isThinking { return true }
        guard let start = startedAt else { return false }
        return now.timeIntervalSince(start) < pulsePeriod
    }
}

struct BrainThinkingIndicator: View {
    let isThinking: Bool

    @State private var startedAt: Date?
    @State private var now: Date = Date()
    @State private var pulse: Bool = false

    private let pulsePeriod: TimeInterval = 0.6

    var body: some View {
        ZStack {
            if BrainVisibility(
                isThinking: isThinking,
                startedAt: startedAt,
                now: now,
                pulsePeriod: pulsePeriod
            ).shouldBeVisible {
                Text("🧠")
                    .font(.system(size: 28))
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(
                        .easeInOut(duration: pulsePeriod / 2)
                            .repeatForever(autoreverses: true),
                        value: pulse
                    )
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
                    .transition(.opacity)
            }
        }
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .onChange(of: isThinking) { _, newValue in
            if newValue { startedAt = Date() }
        }
        .onReceive(
            Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
        ) { t in
            now = t
        }
    }
}
