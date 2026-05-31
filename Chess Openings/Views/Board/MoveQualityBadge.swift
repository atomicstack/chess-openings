import SwiftUI

/// chess.com-style badge: a solid-coloured circle with a white glyph
/// inside (either a short text glyph or an SF Symbol). Animates in
/// with a small overshoot then fades across the final ~30 % of its
/// configured lifetime.
struct MoveQualityBadge: View {
    let quality: MoveQuality
    let size: CGFloat
    let durationMs: Int

    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Circle().fill(quality.color)
            glyphView
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .opacity(opacity)
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        .onAppear {
            let totalSecs = max(0.3, Double(durationMs) / 1000.0)
            withAnimation(.easeOut(duration: 0.18)) {
                scale = 1.2
                opacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.12).delay(0.18)) {
                scale = 1.0
            }
            let fadeDelay = max(0.3, totalSecs - 0.35)
            withAnimation(.easeIn(duration: 0.35).delay(fadeDelay)) {
                opacity = 0
            }
        }
    }

    @ViewBuilder
    private var glyphView: some View {
        switch quality.glyph {
        case .text(let txt):
            // Heavy weight + tight kerning to match the web prototype's
            // bang-style glyphs (!!, ?!, etc.).
            Text(txt)
                .font(.system(
                    size: size * textSizeRatio(for: txt),
                    weight: .heavy,
                    design: .rounded
                ))
                .kerning(txt.count >= 2 ? -1 : 0)
        case .symbol(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .fontWeight(name == "xmark" ? .black : .bold)
                .padding(size * 0.24)
        }
    }

    /// Multi-character glyphs need to be slightly smaller so they fit
    /// on the badge without crowding the rim.
    private func textSizeRatio(for txt: String) -> CGFloat {
        switch txt.count {
        case 1:  return 0.62
        case 2:  return 0.50
        default: return 0.42
        }
    }
}
