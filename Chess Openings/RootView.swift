import SwiftUI
import SwiftData
import Observation

@Observable
final class AppStatus {
    var seedError: Error?
}

struct RootView: View {
    @Environment(AppStatus.self) private var status
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            if status.seedError == nil {
                RootTabsView()
            } else {
                VStack(spacing: 8) {
                    Text("could not load built-in openings")
                        .font(.headline)
                    Text("\(String(describing: status.seedError!))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .task {
            do {
                try SeedLoader().seedIfEmpty(context: modelContext)
            } catch {
                status.seedError = error
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppStatus())
}
