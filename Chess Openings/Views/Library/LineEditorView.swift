import SwiftUI
import SwiftData

struct LineEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let opening: Opening

    @State private var lineName: String = ""
    @State private var sanText: String = ""
    @State private var errorMessage: String?

    private var canSave: Bool {
        !lineName.trimmingCharacters(in: .whitespaces).isEmpty
            && !sanText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("line name") {
                TextField("e.g. main line", text: $lineName)
                    .textInputAutocapitalization(.never)
            }
            Section("moves (san)") {
                TextEditor(text: $sanText)
                    .frame(minHeight: 140)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                Text("enter san plies separated by whitespace or move numbers, e.g. `1. e4 e5 2. Nf3 Nc6`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let msg = errorMessage {
                Section {
                    Text(msg).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("new line")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("save") { save() }
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        let tokens = tokenise(sanText)
        guard !tokens.isEmpty else {
            errorMessage = "no moves entered"
            return
        }
        do {
            let (_, moves) = try PositionBuilder.build(fromSan: tokens)
            let plies: [BookPly] = zip(tokens, moves).map { san, move in
                BookPly(san: san, uci: move.lan)
            }
            let line = Line(name: lineName.trimmingCharacters(in: .whitespaces), plies: plies)
            line.opening = opening
            opening.lines.append(line)
            context.insert(line)
            try? context.save()
            dismiss()
        } catch PositionBuilder.BuildError.illegal(let ply, let san) {
            errorMessage = "illegal move at ply \(ply + 1): \(san)"
        } catch {
            errorMessage = "could not parse moves: \(error)"
        }
    }

    /// splits raw san input into individual ply tokens,
    /// stripping pgn-style move numbers ("1.", "2...") and empty pieces.
    private func tokenise(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .compactMap { token -> String? in
                let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if trimmed.isEmpty { return nil }
                if Int(trimmed) != nil { return nil }
                return trimmed
            }
    }
}
