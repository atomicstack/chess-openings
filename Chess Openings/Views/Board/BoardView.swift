import SwiftUI
import UniformTypeIdentifiers
import ChessKit

/// Drag token representing a source square. Uses file number (1..8) and rank
/// value (1..8) because chesskit's `Square` is not itself `Codable`-friendly
/// for direct transfer, and the pair uniquely identifies a square.
struct SquareToken: Codable, Transferable {
    let file: Int
    let rank: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }

    var square: Square {
        let fileChar = Square.File(file).rawValue
        return Square("\(fileChar)\(rank)")
    }

    init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    init(square: Square) {
        self.file = square.file.number
        self.rank = square.rank.value
    }
}

struct BoardView: View {
    let position: Position
    let orientation: Side
    let highlights: [Square: Set<HighlightKind>]
    let onMove: (Move) -> Void

    @State private var selected: Square?
    @State private var promotionContext: PromotionContext?

    struct PromotionContext: Identifiable {
        let id = UUID()
        let from: Square
        let to: Square
    }

    init(
        position: Position,
        orientation: Side = .white,
        highlights: [Square: Set<HighlightKind>] = [:],
        onMove: @escaping (Move) -> Void = { _ in }
    ) {
        self.position = position
        self.orientation = orientation
        self.highlights = highlights
        self.onMove = onMove
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            VStack(spacing: 0) {
                ForEach(ranks(), id: \.self) { rank in
                    HStack(spacing: 0) {
                        ForEach(files(), id: \.self) { fileNumber in
                            let sq = square(fileNumber: fileNumber, rank: rank)
                            cell(for: sq, fileNumber: fileNumber, rank: rank)
                                .frame(width: side / 8, height: side / 8)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .sheet(item: $promotionContext) { ctx in
            PromotionPickerView(side: sideToMove) { kind in
                completePromotion(ctx: ctx, kind: kind)
            }
        }
    }

    @ViewBuilder
    private func cell(for sq: Square, fileNumber: Int, rank: Int) -> some View {
        let view = SquareView(
            isLight: (fileNumber + rank) % 2 == 1,
            pieceAssetName: assetName(for: position.piece(at: sq)),
            highlights: effectiveHighlights(for: sq)
        )
        .contentShape(Rectangle())
        .onTapGesture { handleTap(on: sq) }
        .dropDestination(for: SquareToken.self) { tokens, _ in
            guard let token = tokens.first else { return false }
            return performDrop(from: token.square, to: sq)
        }

        if let piece = position.piece(at: sq), piece.color == position.sideToMove {
            view.draggable(SquareToken(square: sq))
        } else {
            view
        }
    }

    // MARK: - interaction

    private func handleTap(on sq: Square) {
        if let from = selected {
            if attemptMove(from: from, to: sq) {
                selected = nil
                return
            }
            if let piece = position.piece(at: sq), piece.color == position.sideToMove {
                selected = sq
            } else {
                selected = nil
            }
        } else {
            if let piece = position.piece(at: sq), piece.color == position.sideToMove {
                selected = sq
            }
        }
    }

    @discardableResult
    private func performDrop(from: Square, to: Square) -> Bool {
        let accepted = attemptMove(from: from, to: to)
        if accepted { selected = nil }
        return accepted
    }

    /// Attempts to apply a move from `from` to `to` against a scratch `Board`
    /// copy of `position`. If the move is pending promotion, stores a
    /// `PromotionContext` and defers the final move until the user picks a
    /// promotion piece; returns `true` in that case as well (the drop/tap is
    /// considered accepted).
    private func attemptMove(from: Square, to: Square) -> Bool {
        var board = Board(position: position)
        let legals = board.legalMoves(forPieceAt: from)
        guard legals.contains(to) else { return false }
        guard let move = board.move(pieceAt: from, to: to) else { return false }

        if case .promotion = board.state {
            promotionContext = PromotionContext(from: from, to: to)
            return true
        }

        onMove(move)
        return true
    }

    private func completePromotion(ctx: PromotionContext, kind: Piece.Kind) {
        var board = Board(position: position)
        guard let pending = board.move(pieceAt: ctx.from, to: ctx.to) else {
            promotionContext = nil
            return
        }
        let finalMove = board.completePromotion(of: pending, to: kind)
        promotionContext = nil
        onMove(finalMove)
    }

    private var sideToMove: Side {
        position.sideToMove == .white ? .white : .black
    }

    private func effectiveHighlights(for sq: Square) -> Set<HighlightKind> {
        var result = highlights[sq] ?? []
        if let selected, selected == sq {
            result.insert(.selected)
        }
        if let selected {
            let board = Board(position: position)
            if board.legalMoves(forPieceAt: selected).contains(sq) {
                result.insert(.legalTarget)
            }
        }
        return result
    }

    // MARK: - geometry

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
