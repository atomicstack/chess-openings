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

/// Visual identity for a piece that persists across position updates so that
/// the overlay layer can animate a smooth translation when a piece moves
/// between squares. Same `id` across reconciles means SwiftUI animates the
/// `.position` change instead of cross-fading.
private struct PieceToken: Identifiable {
    let id: UUID
    var color: Piece.Color
    var kind: Piece.Kind
    var square: Square
}

private struct PieceEntry {
    let sq: Square
    let color: Piece.Color
    let kind: Piece.Kind
}

struct BoardView: View {
    let position: Position
    let orientation: Side
    let highlights: [Square: Set<HighlightKind>]
    let onMove: (Move) -> Void

    @State private var selected: Square?
    @State private var promotionContext: PromotionContext?
    @State private var pieceTokens: [PieceToken] = []

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
            let cell = side / 8
            ZStack {
                VStack(spacing: 0) {
                    ForEach(ranks(), id: \.self) { rank in
                        HStack(spacing: 0) {
                            ForEach(files(), id: \.self) { fileNumber in
                                let sq = square(fileNumber: fileNumber, rank: rank)
                                squareCell(for: sq, fileNumber: fileNumber, rank: rank, cellSize: cell)
                            }
                        }
                    }
                }
                .frame(width: side, height: side)

                pieceOverlay(cell: cell)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: fenFingerprint(of: position), initial: true) { _, _ in
            reconcileTokens()
        }
        .sheet(item: $promotionContext) { ctx in
            PromotionPickerView(side: sideToMove) { kind in
                completePromotion(ctx: ctx, kind: kind)
            }
        }
    }

    @ViewBuilder
    private func squareCell(for sq: Square, fileNumber: Int, rank: Int, cellSize: CGFloat) -> some View {
        let view = SquareView(
            isLight: (fileNumber + rank) % 2 == 1,
            highlights: effectiveHighlights(for: sq)
        )
        .frame(width: cellSize, height: cellSize)
        .contentShape(Rectangle())
        .onTapGesture { handleTap(on: sq) }
        .dropDestination(for: SquareToken.self) { tokens, _ in
            guard let token = tokens.first else { return false }
            return performDrop(from: token.square, to: sq)
        }

        if let piece = position.piece(at: sq), piece.color == position.sideToMove {
            view.draggable(SquareToken(square: sq)) {
                Image(assetName(color: piece.color, kind: piece.kind))
                    .resizable().scaledToFit()
                    .frame(width: cellSize, height: cellSize)
                    .padding(4)
            }
        } else {
            view
        }
    }

    private func pieceOverlay(cell: CGFloat) -> some View {
        ZStack {
            ForEach(pieceTokens) { token in
                Image(assetName(color: token.color, kind: token.kind))
                    .resizable()
                    .scaledToFit()
                    .frame(width: cell, height: cell)
                    .padding(4)
                    .position(
                        x: (displayCol(for: token.square) + 0.5) * cell,
                        y: (displayRow(for: token.square) + 0.5) * cell
                    )
            }
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
                // Squares that would capture an opponent piece get a ring
                // indicator instead of the plain legal-target tint.
                if let victim = position.piece(at: sq),
                   victim.color != position.sideToMove {
                    result.insert(.captureTarget)
                } else {
                    result.insert(.legalTarget)
                }
            }
        }
        return result
    }

    // MARK: - piece-token reconciliation

    /// Rebuilds `pieceTokens` against the current `position`, preserving ids
    /// where possible so SwiftUI animates the `.position()` change. First
    /// render (`pieceTokens` empty) populates without animation; subsequent
    /// renders animate via a fast-attack ease-out so the motion starts
    /// immediately on the next frame after the drop.
    private func reconcileTokens() {
        let target = currentPieces()
        if pieceTokens.isEmpty {
            pieceTokens = target.map { PieceToken(id: UUID(), color: $0.color, kind: $0.kind, square: $0.sq) }
            return
        }
        let next = Self.reconcile(old: pieceTokens, against: target)
        withAnimation(.easeOut(duration: 0.09)) {
            pieceTokens = next
        }
    }

    private func currentPieces() -> [PieceEntry] {
        var result: [PieceEntry] = []
        for f in 1...8 {
            for r in 1...8 {
                let sq = square(fileNumber: f, rank: r)
                if let p = position.piece(at: sq) {
                    result.append(PieceEntry(sq: sq, color: p.color, kind: p.kind))
                }
            }
        }
        return result
    }

    private static func reconcile(old: [PieceToken], against target: [PieceEntry]) -> [PieceToken] {
        var unmatched = old
        var result: [PieceToken] = []
        var remaining: [PieceEntry] = []

        // pass 1: stayed-put — same square, same piece
        for entry in target {
            if let idx = unmatched.firstIndex(where: {
                $0.square == entry.sq && $0.color == entry.color && $0.kind == entry.kind
            }) {
                result.append(unmatched.remove(at: idx))
            } else {
                remaining.append(entry)
            }
        }

        // pass 2: match same-color + same-kind nearest (moves, castling, en passant survivor)
        var stillRemaining: [PieceEntry] = []
        for entry in remaining {
            let candidates: [Int] = unmatched.indices.filter { i in
                unmatched[i].color == entry.color && unmatched[i].kind == entry.kind
            }
            if let best = candidates.min(by: {
                squareDistance(unmatched[$0].square, entry.sq) < squareDistance(unmatched[$1].square, entry.sq)
            }) {
                var tok = unmatched.remove(at: best)
                tok.square = entry.sq
                result.append(tok)
            } else {
                stillRemaining.append(entry)
            }
        }

        // pass 3: match same-color any-kind (promotions)
        for entry in stillRemaining {
            let candidates: [Int] = unmatched.indices.filter { i in unmatched[i].color == entry.color }
            if let best = candidates.min(by: {
                squareDistance(unmatched[$0].square, entry.sq) < squareDistance(unmatched[$1].square, entry.sq)
            }) {
                var tok = unmatched.remove(at: best)
                tok.square = entry.sq
                tok.kind = entry.kind
                result.append(tok)
            } else {
                result.append(PieceToken(id: UUID(), color: entry.color, kind: entry.kind, square: entry.sq))
            }
        }

        return result
    }

    private static func squareDistance(_ a: Square, _ b: Square) -> Int {
        let df = a.file.number - b.file.number
        let dr = a.rank.value - b.rank.value
        return df * df + dr * dr
    }

    /// Stable identity for a position used as the `.onChange` key. Uses FEN
    /// because `Position` isn't guaranteed `Equatable` across chesskit updates.
    private func fenFingerprint(of position: Position) -> String {
        FENParser.convert(position: position)
    }

    // MARK: - geometry

    private func ranks() -> [Int] { orientation == .white ? [8,7,6,5,4,3,2,1] : [1,2,3,4,5,6,7,8] }
    private func files() -> [Int] { orientation == .white ? [1,2,3,4,5,6,7,8] : [8,7,6,5,4,3,2,1] }

    private func square(fileNumber: Int, rank: Int) -> Square {
        let fileChar = Square.File(fileNumber).rawValue
        return Square("\(fileChar)\(rank)")
    }

    /// Screen column (0..7 left-to-right) for a square given the orientation.
    private func displayCol(for sq: Square) -> CGFloat {
        let f = CGFloat(sq.file.number - 1)
        return orientation == .white ? f : (7 - f)
    }

    /// Screen row (0..7 top-to-bottom) for a square given the orientation.
    private func displayRow(for sq: Square) -> CGFloat {
        let r = CGFloat(sq.rank.value - 1)
        return orientation == .white ? (7 - r) : r
    }

    private func assetName(color: Piece.Color, kind: Piece.Kind) -> String {
        let c = (color == .white) ? "w" : "b"
        let k: String
        switch kind {
        case .pawn: k = "p"
        case .knight: k = "n"
        case .bishop: k = "b"
        case .rook: k = "r"
        case .queen: k = "q"
        case .king: k = "k"
        }
        return c + k
    }
}

#Preview("standard") { BoardView(position: .standard).padding() }
