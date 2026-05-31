import SwiftUI
import SwiftData

/// Value-based navigation routes used both for normal taps and for
/// the auto-resume flow. UUIDs (not the @Model class instances) so
/// the path is stable across app launches — after a relaunch the
/// SwiftData rehydrates new in-memory objects, but the persistent
/// ids are unchanged.
struct OpeningRoute: Hashable {
    let openingId: UUID
}

struct DrillRoute: Hashable {
    let openingId: UUID
    let lineId: UUID
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
                        NavigationLink(value: OpeningRoute(openingId: o.id)) {
                            row(for: o)
                        }
                    }
                }
                Section("as black") {
                    ForEach(openings.filter { $0.side == .black }) { o in
                        NavigationLink(value: OpeningRoute(openingId: o.id)) {
                            row(for: o)
                        }
                    }
                }
            }
            .navigationTitle("train")
            .navigationDestination(for: OpeningRoute.self) { route in
                if let opening = openings.first(where: { $0.id == route.openingId }) {
                    OpeningDetailView(opening: opening)
                } else {
                    // SwiftData hadn't finished rehydrating when we tried
                    // to navigate; show a spinner so we don't crash and
                    // re-evaluate when the query updates.
                    ProgressView()
                }
            }
            .navigationDestination(for: DrillRoute.self) { route in
                if let opening = openings.first(where: { $0.id == route.openingId }),
                   let line = opening.lines.first(where: { $0.id == route.lineId }) {
                    DrillView(opening: opening, line: line)
                } else {
                    ProgressView()
                }
            }
        }
        // Re-evaluate whenever the queries deliver fresh results. @Query
        // can land empty on first body evaluation and populate a tick
        // later, so a one-shot .task + didAutoResume guard would miss
        // the populated state.
        .onChange(of: persistedPlayouts.count, initial: true) { _, _ in
            autoResumeIfNeeded()
        }
        .onChange(of: openings.count, initial: true) { _, _ in
            autoResumeIfNeeded()
        }
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
        // Wait for the queries to actually deliver data before we
        // decide there's nothing to resume.
        guard !openings.isEmpty else { return }
        // Latest snapshot wins if there's somehow more than one row.
        let latest = persistedPlayouts
            .sorted { $0.savedAt > $1.savedAt }
            .first
        guard let latest else {
            didAutoResume = true
            return
        }
        guard openings.contains(where: { $0.id == latest.openingId }) else {
            // Snapshot points at a missing opening (e.g. seed reload
            // wiped it); clear it lazily on next app run instead of
            // mutating from a view modifier here. Mark resume done
            // so we don't loop.
            didAutoResume = true
            return
        }
        didAutoResume = true
        path.append(OpeningRoute(openingId: latest.openingId))
        path.append(DrillRoute(
            openingId: latest.openingId,
            lineId: latest.lineId
        ))
    }
}
