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
    let bestMoveArrow: BestMoveArrow?
    let moveAnnotation: MoveAnnotation?
    let moveAnnotationDurationMs: Int
    let onMove: (Move) -> Void

    struct BestMoveArrow: Equatable {
        let from: Square
        let to: Square
    }

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
        bestMoveArrow: BestMoveArrow? = nil,
        moveAnnotation: MoveAnnotation? = nil,
        moveAnnotationDurationMs: Int = 1500,
        onMove: @escaping (Move) -> Void = { _ in }
    ) {
        self.position = position
        self.orientation = orientation
        self.highlights = highlights
        self.bestMoveArrow = bestMoveArrow
        self.moveAnnotation = moveAnnotation
        self.moveAnnotationDurationMs = moveAnnotationDurationMs
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

                // Non-source pieces sit below the arrow so the arrow
                // is visible passing over them (especially important
                // for knight moves that cross occupied squares).
                pieceOverlay(cell: cell, excluding: bestMoveArrow?.from)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)

                bestMoveArrowOverlay(cell: cell)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)

                // The source piece floats above the arrow so the
                // piece-on-its-square reads as the owner of the
                // square, with the arrow tail tucked underneath.
                if let from = bestMoveArrow?.from {
                    pieceOverlay(cell: cell, including: from)
                        .frame(width: side, height: side)
                        .allowsHitTesting(false)
                }

                moveAnnotationOverlay(cell: cell)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: fenFingerprint(of: position), initial: true) { _, _ in
            reconcileTokens()
        }
        .onChange(of: bestMoveArrow) { _, arrow in
            // If the user pressed "solution" with an unrelated piece
            // already tapped, drop that selection so the new arrow
            // overlay isn't accompanied by a stale blue legal-target
            // wash from the wrong piece. Keep the selection when it
            // matches the arrow source — that case is "the user picked
            // the right piece".
            guard let arrow else { return }
            if let sel = selected, sel != arrow.from {
                selected = nil
            }
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

        if let piece = position.piece(at: sq), piece.color == userPieceColor {
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

    /// Pass `excluding: sq` to render every piece EXCEPT the one on
    /// that square (used for the under-arrow layer). Pass `including:
    /// sq` to render ONLY the piece on that square (used for the
    /// over-arrow source-piece layer). Pass neither for all pieces.
    /// The same `pieceTokens` array drives both filters so identities
    /// stay stable across reconciles and animations don't double-fire.
    private func pieceOverlay(
        cell: CGFloat,
        excluding: Square? = nil,
        including: Square? = nil
    ) -> some View {
        ZStack {
            ForEach(pieceTokens) { token in
                if shouldRender(token, excluding: excluding, including: including) {
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
    }

    private func shouldRender(
        _ token: PieceToken,
        excluding: Square?,
        including: Square?
    ) -> Bool {
        if let including { return token.square == including }
        if let excluding { return token.square != excluding }
        return true
    }

    @ViewBuilder
    private func bestMoveArrowOverlay(cell: CGFloat) -> some View {
        if let arrow = bestMoveArrow {
            AnimatedMoveArrow(
                route: arrowRoute(from: arrow.from, to: arrow.to, cell: cell),
                cell: cell,
                color: Color.blue.opacity(0.75),
                // Restart the grow animation whenever the move changes.
                animationKey: "\(arrow.from.file.number)\(arrow.from.rank.value)"
                    + "-\(arrow.to.file.number)\(arrow.to.rank.value)"
            )
        }
    }

    /// The polyline the arrow follows: a straight start→end for most
    /// moves, or an L through a corner square for knight moves (long
    /// leg first, then the turn into the destination).
    private func arrowRoute(from: Square, to: Square, cell: CGFloat) -> [CGPoint] {
        let start = center(of: from, cell: cell)
        let end = center(of: to, cell: cell)
        if let corner = ArrowGeometry.knightCorner(
            fromFile: from.file.number, fromRank: from.rank.value,
            toFile: to.file.number, toRank: to.rank.value
        ) {
            return [start, center(fileNumber: corner.file, rankValue: corner.rank, cell: cell), end]
        }
        return [start, end]
    }

    private func center(of sq: Square, cell: CGFloat) -> CGPoint {
        CGPoint(
            x: (displayCol(for: sq) + 0.5) * cell,
            y: (displayRow(for: sq) + 0.5) * cell
        )
    }

    /// Pixel centre of an arbitrary file/rank (1...8), honouring board
    /// orientation — used for the knight corner, which isn't a `Square`
    /// we already hold.
    private func center(fileNumber: Int, rankValue: Int, cell: CGFloat) -> CGPoint {
        let col = orientation == .white
            ? CGFloat(fileNumber - 1) : CGFloat(7 - (fileNumber - 1))
        let row = orientation == .white
            ? CGFloat(7 - (rankValue - 1)) : CGFloat(rankValue - 1)
        return CGPoint(x: (col + 0.5) * cell, y: (row + 0.5) * cell)
    }

    @ViewBuilder
    private func moveAnnotationOverlay(cell: CGFloat) -> some View {
        if let ann = moveAnnotation {
            let centerX = (displayCol(for: ann.square) + 0.5) * cell
            let centerY = (displayRow(for: ann.square) + 0.5) * cell
            let badgeSize = cell * 0.42
            MoveQualityBadge(
                quality: ann.quality,
                size: badgeSize,
                durationMs: moveAnnotationDurationMs
            )
            .position(
                x: centerX + cell * 0.32,
                y: centerY - cell * 0.32
            )
            .id(ann.id)
        }
    }

    // MARK: - interaction

    private func handleTap(on sq: Square) {
        if let from = selected {
            if attemptMove(from: from, to: sq) {
                selected = nil
                return
            }
            if let piece = position.piece(at: sq), piece.color == userPieceColor {
                selected = sq
            } else {
                selected = nil
            }
        } else {
            if let piece = position.piece(at: sq), piece.color == userPieceColor {
                selected = sq
            }
        }
    }

    /// The chesskit colour the user is playing. Used as a HARD guard
    /// on every input path so opponent pieces are never selectable or
    /// draggable, regardless of whatever `position.sideToMove` happens
    /// to be after an undo/restore. See CLAUDE.md "user controls the
    /// wrong side" — this is the input-layer half of that fix.
    private var userPieceColor: Piece.Color { orientation.ckColor }

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
                    // Suppress the blue legal-target wash when the square
                    // already carries a show-and-retry hint tint — the
                    // green hint should stay pure rather than mixing into
                    // a muddy teal with the "you could move here"
                    // indicator. Capture rings are independent info and
                    // are not suppressed.
                    let hasHint = result.contains(.hintFrom) || result.contains(.hintTo)
                    if !hasHint {
                        result.insert(.legalTarget)
                    }
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

/// Filled arrow from `from` (source square center) to `to` (target
/// square center). Shaft is `cell * 0.5` wide; arrowhead tip lands
/// exactly on `to`, with the head flared out so it reads as an arrow
/// rather than a thicker shaft. The shaft is shortened to meet the
/// base of the head so the two segments don't overlap visually.
/// The board arrow as a fillable shape that follows a `route`
/// polyline (two points for a plain move, three for an L-shaped
/// knight move) and extends to `progress` of its full length — so
/// animating `progress` grows the arrow out from its source. The
/// head scales up alongside the growth and points along whichever
/// route segment the tip currently sits on.
private struct MoveArrow: Shape {
    var route: [CGPoint]
    var cell: CGFloat
    var progress: CGFloat

    // Driving `progress` through `animatableData` makes SwiftUI
    // interpolate the path each frame, so `withAnimation` smoothly
    // grows the arrow rather than snapping between lengths.
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(progress, 0), 1)
        guard route.count >= 2 else { return Path() }
        let fullLength = ArrowGeometry.routeLength(route)
        guard fullLength > 0.001, clamped > 0.001 else { return Path() }

        let currentLength = fullLength * clamped
        // Head grows in from nothing as the arrow extends past a cell.
        let headScale = min(1, currentLength / cell)
        let shaftWidth = cell * 0.32
        let headLength = cell * 0.40 * headScale
        let headWidth = cell * 0.65 * headScale

        guard let tipInfo = ArrowGeometry.pointAtRouteDistance(
            route, distance: currentLength
        ) else { return Path() }

        var path = Path()

        // Shaft: a stroked polyline from the source up to where the
        // head begins. `strokedPath` turns the centreline into a
        // fillable outline, which lets the shaft bend at the knight
        // corner without hand-rolling an offset polygon.
        let shaftEnd = max(0, currentLength - headLength)
        if shaftEnd > 0.001 {
            let points = ArrowGeometry.polyline(route, from: 0, to: shaftEnd)
            if points.count >= 2 {
                var centreline = Path()
                centreline.move(to: points[0])
                for point in points.dropFirst() { centreline.addLine(to: point) }
                path.addPath(centreline.strokedPath(
                    StrokeStyle(lineWidth: shaftWidth, lineCap: .round, lineJoin: .round)
                ))
            }
        }

        // Head: a triangle at the tip, aligned with the local heading.
        let angle = tipInfo.angle
        let tip = tipInfo.point
        let ux = cos(angle)
        let uy = sin(angle)
        let px = -uy
        let py = ux
        let baseX = tip.x - ux * headLength
        let baseY = tip.y - uy * headLength
        let halfHead = headWidth / 2
        var head = Path()
        head.move(to: CGPoint(x: baseX + px * halfHead, y: baseY + py * halfHead))
        head.addLine(to: tip)
        head.addLine(to: CGPoint(x: baseX - px * halfHead, y: baseY - py * halfHead))
        head.closeSubpath()
        path.addPath(head)

        return path
    }
}

/// Hosts the animated board arrow. Owns the growth `progress` and
/// runs the grow → hold → re-pulse loop: snap to a short stub, grow
/// to full over ~350ms, hold, then snap back and regrow. The hold
/// doubles every cycle (up to ~41s) so the arrow pulses a few times
/// to draw the eye, then settles to effectively static. Mirrors the
/// Android `BoardArrowOverlay`. `animationKey` restarts the loop when
/// the move changes; the task auto-cancels when the arrow disappears.
private struct AnimatedMoveArrow: View {
    let route: [CGPoint]
    let cell: CGFloat
    let color: Color
    let animationKey: String

    private static let stub: CGFloat = 0.35

    @State private var progress: CGFloat = AnimatedMoveArrow.stub

    var body: some View {
        MoveArrow(route: route, cell: cell, progress: progress)
            .fill(color)
            .task(id: animationKey) {
                var holdMs: UInt64 = 650
                while !Task.isCancelled {
                    progress = Self.stub
                    try? await Task.sleep(for: .milliseconds(100))
                    if Task.isCancelled { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        progress = 1
                    }
                    try? await Task.sleep(for: .milliseconds(350))
                    try? await Task.sleep(for: .milliseconds(holdMs))
                    holdMs = min(holdMs * 2, 41_600)
                }
            }
    }
}

#Preview("standard") { BoardView(position: .standard).padding() }
