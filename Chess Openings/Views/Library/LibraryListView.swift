import SwiftUI
import SwiftData

struct LibraryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Opening.name)]) private var openings: [Opening]
    @State private var showingNew = false

    private var seedOpenings: [Opening] { openings.filter { $0.isSeed } }
    private var userOpenings: [Opening] { openings.filter { !$0.isSeed } }

    var body: some View {
        NavigationStack {
            List {
                Section("seed openings") {
                    ForEach(seedOpenings) { o in
                        NavigationLink { OpeningDetailView(opening: o) } label: { row(for: o) }
                    }
                }
                Section("yours") {
                    ForEach(userOpenings) { o in
                        NavigationLink { OpeningDetailView(opening: o) } label: { row(for: o) }
                    }
                    .onDelete(perform: deleteUserOpening)
                }
            }
            .navigationTitle("library")
            .toolbar {
                Button {
                    showingNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("new opening")
            }
            .sheet(isPresented: $showingNew) {
                // placeholder; replaced with NewOpeningView in task 9.2
                NavigationStack {
                    Text("new opening")
                        .navigationTitle("new opening")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("cancel") { showingNew = false }
                            }
                        }
                }
            }
        }
    }

    private func row(for o: Opening) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(o.name).font(.body)
                Text("\(o.lines.count) lines · \(o.side == .white ? "white" : "black")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let e = o.eco {
                Text(e).font(.caption2).monospaced().foregroundStyle(.secondary)
            }
        }
    }

    private func deleteUserOpening(at offsets: IndexSet) {
        let list = userOpenings
        for index in offsets {
            guard index < list.count else { continue }
            context.delete(list[index])
        }
        try? context.save()
    }
}
