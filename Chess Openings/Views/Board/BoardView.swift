import SwiftUI
import ChessKit

struct BoardView: View {
    let position: Position
    let orientation: Side
    let highlights: [Square: Set<HighlightKind>]

    init(position: Position, orientation: Side = .white, highlights: [Square: Set<HighlightKind>] = [:]) {
        self.position = position
        self.orientation = orientation
        self.highlights = highlights
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            VStack(spacing: 0) {
                ForEach(ranks(), id: \.self) { rank in
                    HStack(spacing: 0) {
                        ForEach(files(), id: \.self) { fileNumber in
                            let sq = square(fileNumber: fileNumber, rank: rank)
                            SquareView(
                                isLight: (fileNumber + rank) % 2 == 1,
                                pieceAssetName: assetName(for: position.piece(at: sq)),
                                highlights: highlights[sq] ?? []
                            )
                            .frame(width: side / 8, height: side / 8)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func ranks() -> [Int] { orientation == .white ? [8,7,6,5,4,3,2,1] : [1,2,3,4,5,6,7,8] }
    private func files() -> [Int] { orientation == .white ? [1,2,3,4,5,6,7,8] : [8,7,6,5,4,3,2,1] }

    private func square(fileNumber: Int, rank: Int) -> Square {
        // chesskit 0.17.0 exposes only Square(_ notation:) publicly; build notation
        // from the 1-based file number and rank.
        let fileChar = Square.File(fileNumber).rawValue
        return Square("\(fileChar)\(rank)")
    }

    private func assetName(for piece: Piece?) -> String? {
        guard let p = piece else { return nil }
        let color = (p.color == .white) ? "w" : "b"
        let kind: String
        switch p.kind {
        case .pawn: kind = "p"
        case .knight: kind = "n"
        case .bishop: kind = "b"
        case .rook: kind = "r"
        case .queen: kind = "q"
        case .king: kind = "k"
        }
        return color + kind
    }
}

#Preview("standard") { BoardView(position: .standard).padding() }
