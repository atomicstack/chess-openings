import SwiftUI
import SwiftData

/// Typed routes for `OpeningListView`'s `NavigationStack`. UUID-based
/// so the path is stable across launches (rehydrated SwiftData
/// objects get new in-memory identity; their persistent ids don't).
enum TrainRoute: Hashable {
    case opening(UUID)
    case drill(openingId: UUID, lineId: UUID)
}

struct OpeningListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Opening.name)]) private var openings: [Opening]
    @State private var routes: [TrainRoute] = []
    @State private var didAutoResume = false

    var body: some View {
        NavigationStack(path: $routes) {
            List {
                Section("as white") {
                    ForEach(openings.filter { $0.side == .white }) { o in
                        NavigationLink { OpeningDetailView(opening: o) } label: { row(for: o) }
                    }
                }
                Section("as black") {
                    ForEach(openings.filter { $0.side == .black }) { o in
                        NavigationLink { OpeningDetailView(opening: o) } label: { row(for: o) }
                    }
                }
            }
            .navigationTitle("train")
            // navigationDestination is only used by the auto-resume
            // path append. User taps use closure-style NavigationLinks
            // above — mixing both styles in a single NavigationStack
            // works fine; closures push directly, values route through
            // the destination handlers below.
            .navigationDestination(for: TrainRoute.self) { route in
                destinationView(for: route)
            }
        }
        .task { await autoResumeIfNeeded() }
    }

    @ViewBuilder
    private func destinationView(for route: TrainRoute) -> some View {
        switch route {
        case .opening(let id):
            if let opening = openings.first(where: { $0.id == id }) {
                OpeningDetailView(opening: opening)
            } else {
                // SwiftData hadn't rehydrated yet — bail loudly so we
                // can spot it on device instead of silently navigating
                // to an empty page.
                Text("opening not found").foregroundStyle(.red)
            }
        case .drill(let openingId, let lineId):
            if let opening = openings.first(where: { $0.id == openingId }),
               let line = opening.lines.first(where: { $0.id == lineId }) {
                DrillView(opening: opening, line: line)
            } else {
                Text("line not found").foregroundStyle(.red)
            }
        }
    }

    private func row(for o: Opening) -> some View {
        let learned = o.lines.filter { $0.mastery?.isLearned == true }.count
        return HStack {
            VStack(alignment: .leading) {
                Text(o.name).font(.body)
                Text("\(learned)/\(o.lines.count) lines learned")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                if let e = o.eco { Text(e).font(.caption2).monospaced().foregroundStyle(.secondary) }
                ProgressBarView(current: learned, total: o.lines.count).frame(width: 60)
            }
        }
    }

    /// Direct fetch from the model context so we don't have to race
    /// `@Query`. Waits one render tick for SwiftData to finish first-
    /// run setup, then looks for the most recent persisted playout
    /// and, if found, pushes the matching route stack.
    @MainActor
    private func autoResumeIfNeeded() async {
        guard !didAutoResume else { return }
        try? await Task.sleep(for: .milliseconds(50))
        didAutoResume = true
        let descriptor = FetchDescriptor<PersistedPlayoutState>(
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        guard let latest = try? modelContext.fetch(descriptor).first else { return }
        // Be defensive: only navigate if the saved opening + line still
        // exist (e.g. a seed reload between launches could have wiped
        // them). Fetching the Opening directly avoids depending on
        // the `openings` @Query being populated by this point.
        let oid = latest.openingId
        let lid = latest.lineId
        let openingDescriptor = FetchDescriptor<Opening>(
            predicate: #Predicate<Opening> { $0.id == oid }
        )
        guard let opening = try? modelContext.fetch(openingDescriptor).first,
              opening.lines.contains(where: { $0.id == lid }) else {
            return
        }
        routes = [
            .opening(oid),
            .drill(openingId: oid, lineId: lid)
        ]
    }
}
