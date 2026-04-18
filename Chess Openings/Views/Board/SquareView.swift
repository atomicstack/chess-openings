import SwiftUI

struct SquareView: View {
    let isLight: Bool
    let highlights: Set<HighlightKind>

    var body: some View {
        ZStack {
            Rectangle().fill(isLight ? Color(white: 0.96) : Color(white: 0.80))
            ForEach(Array(highlights), id: \.self) { h in
                Rectangle().fill(h.overlayColor)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
