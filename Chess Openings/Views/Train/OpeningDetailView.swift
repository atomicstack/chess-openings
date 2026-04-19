import SwiftUI

struct OpeningDetailView: View {
    let opening: Opening

    var body: some View {
        List {
            if let d = opening.openingDescription, !d.isEmpty {
                Section { Text(d).font(.callout) }
            }
            if !mastersLines.isEmpty {
                Section("master games") {
                    ForEach(mastersLines) { line in
                        NavigationLink { DrillView(opening: opening, line: line) } label: { row(for: line) }
                    }
                }
            }
            if !openLines.isEmpty {
                Section("online play (2200+)") {
                    ForEach(openLines) { line in
                        NavigationLink { DrillView(opening: opening, line: line) } label: { row(for: line) }
                    }
                }
            }
        }
        .navigationTitle(opening.name)
        .toolbar {
            if let first = opening.lines.first {
                NavigationLink("drill all") { DrillView(opening: opening, line: first) }
            }
            if !opening.isSeed {
                NavigationLink {
                    LineEditorView(opening: opening)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("add line")
            }
        }
    }

    private var mastersLines: [Line] { opening.lines.filter { $0.source == .masters } }
    private var openLines:    [Line] { opening.lines.filter { $0.source == .open    } }

    private func row(for line: Line) -> some View {
        let preview = line.plies.prefix(6).map { $0.san }.joined(separator: " ")
        let streak = line.mastery?.correctStreak ?? 0
        let learned = line.mastery?.isLearned ?? false
        return VStack(alignment: .leading) {
            Text(line.name).font(.body)
            Text(preview).font(.caption).monospaced().foregroundStyle(.secondary).lineLimit(1)
            if learned {
                Text("✓ learned").font(.caption2).foregroundStyle(.blue)
            } else {
                Text("streak: \(streak)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
