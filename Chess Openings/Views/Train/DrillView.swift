import SwiftUI
import SwiftData
import ChessKit

struct DrillView: View {
    let opening: Opening
    let line: Line

    @Query private var settingsList: [UserSettings]
    @State private var session: DrillSession?
    @State private var hintShown: Bool = false
    @State private var solutionShown: Bool = false
    @State private var showSettingsSheet: Bool = false
    @State private var audio: AudioService?

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
        .navigationTitle("\(opening.name) — \(line.name)")
        .toolbar(.hidden, for: .tabBar)
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
        .onChange(of: session?.history.count ?? 0) { _, _ in
            // Any applied move — user, reply, autoplay, undo, reset —
            // invalidates whatever hint/solution the user had visible.
            // Force them to explicitly re-enable for the next move.
            hintShown = false
            solutionShown = false
        }
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
        HStack(alignment: .top, spacing: 8) {
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 4) {
                ForEach(Array(s.history.enumerated()), id: \.offset) { i, move in
                    let pre = i < s.preMovePositions.count ? s.preMovePositions[i] : Position.standard
                    let san = SanCodec.format(move, in: pre)
                    Text(sanLabel(ply: i, san: san))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(progressLabel(for: s))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func progressLabel(for s: DrillSession) -> String {
        let p = DrillProgress.userMoves(
            historyCount: s.history.count,
            totalPlies: line.plies.count,
            side: opening.side
        )
        return "\(p.played)/\(p.total)"
    }

    private func controlsRow(for s: DrillSession) -> some View {
        HStack(spacing: 16) {
            Button {
                hintShown.toggle()
                if hintShown { solutionShown = false }
            } label: {
                Label(hintShown ? "hide hint" : "hint", systemImage: "lightbulb")
            }
            .tint(.green)
            .disabled(s.status == .lineComplete)

            Button {
                solutionShown.toggle()
                if solutionShown { hintShown = false }
            } label: {
                Label(solutionShown ? "hide solution" : "solution", systemImage: "eye")
            }
            .tint(.blue)
            .disabled(s.status == .lineComplete)

            Button {
                s.undo()
            } label: {
                Label("undo", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)
            .disabled(s.history.isEmpty)

            Button {
                s.reset()
                if opening.side == .black {
                    scheduleBlackSideAutoplay(on: s)
                }
            } label: {
                Label("reset", systemImage: "arrow.clockwise")
            }
            .tint(.red)
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
        s.scriptedReplyDelayMs = 750
        let player = AudioService(isEnabled: { [settingsList] in
            settingsList.first?.soundsEnabled ?? true
        })
        s.onMoveApplied = { move, pre, post, byUser in
            let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: byUser)
            player.play(sfx)
        }
        audio = player
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
            return "line complete ✓"
        }
    }

    private func promptColor(for s: DrillSession) -> Color {
        switch s.status {
        case .waitingForUser, .evaluating: return .primary
        case .mistake:                      return .red
        case .lineComplete:                 return .green
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
        if (hintShown || solutionShown), s.status != .lineComplete,
           s.history.count < line.plies.count,
           let move = SANParser.parse(move: line.plies[s.history.count].san, in: s.position) {
            // Hint shows only the source square; solution reveals the
            // full move by adding the destination square.
            map[move.start, default: []].insert(.hintFrom)
            if solutionShown {
                map[move.end, default: []].insert(.hintTo)
            }
        }
        if case .mistake(let book, _) = s.status {
            map[book.move.start, default: []].insert(.hintFrom)
            map[book.move.end, default: []].insert(.hintTo)
        }
        return map
    }
}
