import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("chess openings")
                .font(.title)
            Text("wiring in progress")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview { RootView() }
