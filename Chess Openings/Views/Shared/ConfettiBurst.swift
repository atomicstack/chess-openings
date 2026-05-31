import SwiftUI

/// One-shot confetti animation. Pass a fresh `trigger` value to fire
/// a new burst — any non-nil change reseeds the particles and resets
/// the elapsed clock. Renders zero state when no trigger has fired or
/// when the burst has finished.
struct ConfettiBurst: View {
    let trigger: Date?

    private let particleCount = 36
    private let duration: TimeInterval = 2.0

    @State private var particles: [Particle] = []
    @State private var startedAt: Date?

    private struct Particle {
        let originX: CGFloat
        let velocityX: CGFloat
        let velocityY: CGFloat
        let rotationRate: Double
        let color: Color
        let size: CGFloat
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                guard let startedAt else { return }
                let elapsed = tl.date.timeIntervalSince(startedAt)
                guard elapsed <= duration else { return }
                let t = CGFloat(elapsed)
                let alpha = max(0, 1 - elapsed / duration)
                for p in particles {
                    let x = p.originX * size.width + p.velocityX * t
                    let y = -20 + p.velocityY * t
                    let rot = Angle(degrees: p.rotationRate * 360 * Double(t))
                    ctx.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: rot)
                        layer.opacity = alpha
                        var path = Path()
                        path.addRect(CGRect(
                            x: -p.size / 2, y: -p.size / 2,
                            width: p.size, height: p.size
                        ))
                        layer.fill(path, with: .color(p.color))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .onChange(of: trigger) { _, new in
            guard new != nil else { return }
            particles = generateParticles()
            startedAt = Date()
        }
    }

    private func generateParticles() -> [Particle] {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .blue, .purple, .pink
        ]
        return (0..<particleCount).map { _ in
            Particle(
                originX: CGFloat.random(in: 0...1),
                velocityX: CGFloat.random(in: -80...80),
                velocityY: CGFloat.random(in: 220...360),
                rotationRate: Double.random(in: -2...2),
                color: colors.randomElement() ?? .red,
                size: CGFloat.random(in: 6...12)
            )
        }
    }
}
