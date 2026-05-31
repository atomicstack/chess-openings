import SwiftUI

struct PlayoutPromptRow: View {
    let session: EnginePlayoutSession
    let onAcceptEngineResign: () -> Void
    let onDeclineEngineResign: () -> Void

    var body: some View {
        HStack {
            content
            Spacer()
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var content: some View {
        switch session.status {
        case .waitingForUser:
            Text("your move").font(.callout)
        case .engineThinking:
            Text("stockfish thinking…")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .drawOffered(byUser: true):
            Text("draw offered — awaiting engine reply")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .drawOffered(byUser: false):
            Text("stockfish offers a draw")
                .font(.callout)
        case .gameOver(let reason):
            gameOverContent(reason)
        }
    }

    @ViewBuilder
    private func gameOverContent(_ reason: GameOverReason) -> some View {
        switch reason {
        case .checkmate(let winner):
            Text(winner == session.userSide
                 ? "checkmate — you win"
                 : "checkmate — you lose")
                .font(.callout)
                .foregroundStyle(winner == session.userSide ? .green : .red)
        case .stalemate:
            Text("draw by stalemate").font(.callout)
        case .fiftyMoveRule:
            Text("draw by 50-move rule").font(.callout)
        case .threefoldRepetition:
            Text("draw by repetition").font(.callout)
        case .insufficientMaterial:
            Text("draw by insufficient material").font(.callout)
        case .drawAgreed:
            Text("draw agreed").font(.callout)
        case .userResigned:
            Text("you resigned").font(.callout)
        case .engineResigned(let accepted):
            switch accepted {
            case .none:
                HStack(spacing: 8) {
                    Text("stockfish offers to resign").font(.callout)
                    Button("accept (win)", action: onAcceptEngineResign)
                        .buttonStyle(.borderedProminent)
                    Button("keep playing", action: onDeclineEngineResign)
                        .buttonStyle(.bordered)
                }
            case .some(true):
                Text("stockfish resigned — you win")
                    .font(.callout)
                    .foregroundStyle(.green)
            case .some(false):
                // Defensive: declineEngineResignation resets to
                // .waitingForUser so this case shouldn't be reached
                // through the model. Render nothing.
                EmptyView()
            }
        }
    }
}
