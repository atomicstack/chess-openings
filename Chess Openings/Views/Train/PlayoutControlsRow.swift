import SwiftUI

struct PlayoutControlsRow: View {
    let session: EnginePlayoutSession
    @Binding var hintShown: Bool
    @Binding var solutionShown: Bool
    let onResign: () -> Void
    let onOfferDraw: () -> Void
    let onExitPlayout: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Button {
                    hintShown.toggle()
                    if hintShown { solutionShown = false }
                } label: {
                    Label(hintShown ? "hide hint" : "hint",
                          systemImage: "lightbulb")
                }
                .tint(.green)
                .disabled(!isLive)
                .frame(maxWidth: .infinity)

                Button {
                    solutionShown.toggle()
                    if solutionShown { hintShown = false }
                } label: {
                    Label(solutionShown ? "hide" : "best move",
                          systemImage: "eye")
                }
                .tint(.blue)
                .disabled(!isLive)
                .frame(maxWidth: .infinity)

                Button {
                    session.undo()
                } label: {
                    Label("undo", systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)
                .disabled(!isLive || session.history.isEmpty)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 0) {
                Button(action: onOfferDraw) {
                    Label("draw", systemImage: "equal.circle")
                }
                .tint(.gray)
                .disabled(!isLive)
                .frame(maxWidth: .infinity)

                Button(role: .destructive, action: onResign) {
                    Label("resign", systemImage: "flag")
                }
                .disabled(!isLive)
                .frame(maxWidth: .infinity)

                Button(action: onExitPlayout) {
                    Label("exit", systemImage: "xmark")
                }
                .tint(.gray)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    private var isLive: Bool {
        switch session.status {
        case .waitingForUser:   return true
        case .engineThinking:   return false
        case .drawOffered:      return false
        case .gameOver:         return false
        }
    }
}
