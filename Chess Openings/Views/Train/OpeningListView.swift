import SwiftUI
import SwiftData

/// Value-based navigation route used when auto-resuming a persisted
/// playout. Wraps `Opening` + `Line` so both can be pushed onto the
/// NavigationStack's `path` in one append.
struct DrillRoute: Hashable {
    let opening: Opening
    let line: Line
}

struct OpeningListView: View {
    @Query(sort: [SortDescriptor(\Opening.name)]) private var openings: [Opening]
    @Query private var persistedPlayouts: [PersistedPlayoutState]
    @State private var path = NavigationPath()
    @State private var didAutoResume = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("as white") {
                    ForEach(openings.filter { $0.side == .white }) { o in
                        NavigationLink(value: o) { row(for: o) }
                    }
                }
                Section("as black") {
                    ForEach(openings.filter { $0.side == .black }) { o in
                        NavigationLink(value: o) { row(for: o) }
                    }
                }
            }
            .navigationTitle("train")
            .navigationDestination(for: Opening.self) { o in
                OpeningDetailView(opening: o)
            }
            .navigationDestination(for: DrillRoute.self) { route in
                DrillView(opening: route.opening, line: route.line)
            }
        }
        // Auto-resume a saved playout on first appearance. The latest
        // snapshot wins if there's somehow more than one persisted row.
        .task { autoResumeIfNeeded() }
    }

    private func row(for o: Opening) -> some View {
        let learned = o.lines.filter { $0.mastery?.isLearned == true }.count
        return HStack {
            VStack(alignment: .leading) {
                Text(o.name).font(.body)
                Text("\(o.lines.count) lines · \(learned)/\(o.lines.count) learned")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                if let e = o.eco { Text(e).font(.caption2).monospaced().foregroundStyle(.secondary) }
                ProgressBarView(current: learned, total: o.lines.count).frame(width: 60)
            }
        }
    }

    private func autoResumeIfNeeded() {
        guard !didAutoResume else { return }
        didAutoResume = true
        let latest = persistedPlayouts
            .sorted { $0.savedAt > $1.savedAt }
            .first
        guard let latest,
              let opening = openings.first(where: { $0.id == latest.openingId }),
              let line = opening.lines.first(where: { $0.id == latest.lineId }) else {
            return
        }
        path.append(opening)
        path.append(DrillRoute(opening: opening, line: line))
    }
}
