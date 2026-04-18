import SwiftUI
import SwiftData

struct OpeningListView: View {
    @Query(sort: [SortDescriptor(\Opening.name)]) private var openings: [Opening]

    var body: some View {
        NavigationStack {
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
}
