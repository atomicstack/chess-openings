import SwiftUI
import ChessKit

struct PromotionPickerView: View {
    let side: Side
    let onChoose: (Piece.Kind) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("promote to").font(.headline)
            HStack(spacing: 20) {
                ForEach([Piece.Kind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                    Button { onChoose(kind) } label: {
                        Image(assetName(kind)).resizable().scaledToFit().frame(width: 56, height: 56)
                    }
                }
            }
        }.padding()
    }

    private func assetName(_ kind: Piece.Kind) -> String {
        let c = side == .white ? "w" : "b"
        switch kind {
        case .queen: return c + "q"
        case .rook: return c + "r"
        case .bishop: return c + "b"
        case .knight: return c + "n"
        default: return c + "q"
        }
    }
}
