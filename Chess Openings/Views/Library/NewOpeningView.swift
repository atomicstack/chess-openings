import SwiftUI
import SwiftData

struct NewOpeningView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var eco: String = ""
    @State private var side: Side = .white

    private static let startingFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("name") {
                    TextField("opening name", text: $name)
                        .textInputAutocapitalization(.never)
                }
                Section("eco") {
                    TextField("e.g. c50", text: $eco)
                        .textInputAutocapitalization(.never)
                }
                Section("side") {
                    Picker("side", selection: $side) {
                        Text("white").tag(Side.white)
                        Text("black").tag(Side.black)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("new opening")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("create") { create() }
                        .disabled(!canCreate)
                }
            }
        }
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEco = eco.trimmingCharacters(in: .whitespaces)
        let opening = Opening(
            name: trimmedName,
            eco: trimmedEco.isEmpty ? nil : trimmedEco,
            side: side,
            rootFen: Self.startingFen,
            isSeed: false
        )
        context.insert(opening)
        try? context.save()
        dismiss()
    }
}
