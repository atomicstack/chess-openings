import SwiftUI
import SwiftData
import ChessKit

struct DrillView: View {
    let opening: Opening
    let line: Line

    @Query private var settingsList: [UserSettings]
    @State private var session: DrillSession?
    @State private var hintShown: Bool = false
    @State private var showSettingsSheet: Bool = false

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        VStack(spacing: 12) {
            if let s = session {
                BoardView(
                    position: s.position,
                    orientation: opening.side,
                    highlights: boardHighlights(for: s),
                    onMove: { move in
                        Task { await s.submit(move) }
                    }
                )
                .padding(.horizontal)

                promptRow(for: s)
                moveListRow(for: s)
                controlsRow(for: s)
            } else {
                ProgressView()
            }
            Spacer(minLength: 0)
        }
        .navigationTitle(line.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettingsSheet = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("settings")
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            // SettingsView is wired up in phase 8; placeholder for now.
            VStack(spacing: 16) {
                Text("settings").font(.headline)
                Text("coming soon").foregroundStyle(.secondary)
                Button("close") { showSettingsSheet = false }
            }
            .padding()
            .presentationDetents([.medium])
        }
        .onAppear { startSessionIfNeeded() }
    }

    // MARK: - subviews

    private func promptRow(for s: DrillSession) -> some View {
        HStack {
            Text(promptText(for: s))
                .font(.callout)
                .foregroundStyle(promptColor(for: s))
            Spacer()
        }
        .padding(.horizontal)
    }

    private func moveListRow(for s: DrillSession) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(s.history.enumerated()), id: \.offset) { i, move in
                    let pre = i < s.preMovePositions.count ? s.preMovePositions[i] : Position.standard
                    let san = SanCodec.format(move, in: pre)
                    Text(sanLabel(ply: i, san: san))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private func controlsRow(for s: DrillSession) -> some View {
        HStack(spacing: 16) {
            Button {
                hintShown.toggle()
            } label: {
                Label(hintShown ? "hide hint" : "hint", systemImage: "lightbulb")
            }
            .disabled(s.status == .lineComplete)

            Button {
                hintShown = false
                s.undo()
            } label: {
                Label("undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(s.history.isEmpty)

            Button {
                hintShown = false
                s.reset()
                if opening.side == .black {
                    scheduleBlackSideAutoplay(on: s)
                }
            } label: {
                Label("reset", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal)
    }

    // MARK: - state helpers

    private func startSessionIfNeeded() {
        guard session == nil else { return }
        let snapshot = LineSnapshot(plies: line.plies)
        let oracle = LineBookOracle(plies: line.plies)
        let mode = settings?.drillMode ?? .strict
        let threshold = settings?.masteryThreshold ?? 3
        let initialStreak = line.mastery?.correctStreak ?? 0
        let s = DrillSession(
            line: snapshot,
            oracle: oracle,
            mode: mode,
            masteryThreshold: threshold,
            initialStreak: initialStreak
        )
        session = s
        if opening.side == .black {
            scheduleBlackSideAutoplay(on: s)
        }
    }

    /// For black-side openings, wait ~750ms after the board is shown before
    /// auto-playing white's first scripted move. Gives the user a moment to
    /// orient themselves instead of seeing white's move fly in on appear.
    private func scheduleBlackSideAutoplay(on s: DrillSession) {
        Task {
            try? await Task.sleep(for: .milliseconds(750))
            s.autoplayNextBookPly()
        }
    }

    private func promptText(for s: DrillSession) -> String {
        switch s.status {
        case .waitingForUser:
            return "your move"
        case .evaluating:
            return "thinking..."
        case .mistake(let book, _):
            return "book says \(book.san) — try again"
        case .lineComplete:
            return "line complete"
        }
    }

    private func promptColor(for s: DrillSession) -> Color {
        switch s.status {
        case .waitingForUser, .evaluating: return .primary
        case .mistake:                      return .red
        case .lineComplete:                 return .blue
        }
    }

    private func sanLabel(ply: Int, san: String) -> String {
        // ply 0 is white's first move -> "1." prefix, ply 1 is black's -> no prefix
        if ply % 2 == 0 {
            return "\(ply / 2 + 1).\(san)"
        }
        return san
    }

    private func boardHighlights(for s: DrillSession) -> [Square: Set<HighlightKind>] {
        var map: [Square: Set<HighlightKind>] = [:]
        if let last = s.lastAppliedMove {
            map[last.start, default: []].insert(.lastMove)
            map[last.end, default: []].insert(.lastMove)
        }
        if hintShown, s.status != .lineComplete,
           s.history.count < line.plies.count,
           let move = SANParser.parse(move: line.plies[s.history.count].san, in: s.position) {
            map[move.start, default: []].insert(.hintFrom)
            map[move.end, default: []].insert(.hintTo)
        }
        if case .mistake(let book, _) = s.status {
            map[book.move.start, default: []].insert(.hintFrom)
            map[book.move.end, default: []].insert(.hintTo)
        }
        return map
    }
}
