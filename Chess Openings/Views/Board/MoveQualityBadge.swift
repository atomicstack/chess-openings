import SwiftUI

struct MoveQualityBadge: View {
    let quality: MoveQuality
    let size: CGFloat
    let durationMs: Int

    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0

    var body: some View {
        Image(systemName: quality.iconName)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(quality.color)
            .padding(size * 0.12)
            .background(
                Circle().fill(.white)
            )
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .onAppear {
                let totalSecs = max(0.3, Double(durationMs) / 1000.0)
                // pop in (0.18 s) — overshoot 1.2, then settle to 1.0
                withAnimation(.easeOut(duration: 0.18)) {
                    scale = 1.2
                    opacity = 1.0
                }
                withAnimation(.easeIn(duration: 0.12).delay(0.18)) {
                    scale = 1.0
                }
                // fade out across the last ~30 % of the badge's lifetime
                let fadeDelay = max(0.3, totalSecs - 0.35)
                withAnimation(.easeIn(duration: 0.35).delay(fadeDelay)) {
                    opacity = 0
                }
            }
    }
}
