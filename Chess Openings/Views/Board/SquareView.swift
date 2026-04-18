import SwiftUI

struct SquareView: View {
    let isLight: Bool
    let highlights: Set<HighlightKind>

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lineWidth = side / 10
            ZStack {
                Rectangle().fill(isLight ? Color(white: 0.96) : Color(white: 0.80))
                ForEach(rectHighlights, id: \.self) { h in
                    Rectangle().fill(h.overlayColor)
                }
                if highlights.contains(.captureTarget) {
                    // Circle diameter = side − lineWidth so the outer edge
                    // of the stroke sits flush with the square edge at the
                    // cardinal points (stroke draws half inside / half
                    // outside the path).
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: lineWidth)
                        .frame(width: side - lineWidth, height: side - lineWidth)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var rectHighlights: [HighlightKind] {
        highlights.filter { $0 != .captureTarget }
    }
}
