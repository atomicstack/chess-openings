import SwiftUI

/// One-shot firework-style confetti animation. Pass a fresh `trigger`
/// value (any non-nil `Date` change) to fire a new burst. Particles
/// launch radially from a central point with random outward velocities,
/// then gravity pulls them down for the remainder of the animation.
struct ConfettiBurst: View {
    let trigger: Date?

    private let particleCount = 110
    private let duration: TimeInterval = 2.4
    /// Pixels per second^2. Positive = downward.
    private let gravity: CGFloat = 480
    /// Range of radial launch speeds (px/sec).
    private let speedRange: ClosedRange<CGFloat> = 240...520

    @State private var particles: [Particle] = []
    @State private var startedAt: Date?

    private struct Particle {
        let originX: CGFloat   // fraction of width, jittered around 0.5
        let originY: CGFloat   // fraction of height, jittered around 0.4
        let velocityX: CGFloat // initial outward velocity (px/sec)
        let velocityY: CGFloat // initial outward velocity (px/sec, negative = up)
        let rotationRate: Double
        let color: Color
        let size: CGFloat
        let shape: Shape

        enum Shape { case square, circle }
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
                    // kinematic: x(t) = x0 + vx0*t
                    //            y(t) = y0 + vy0*t + 0.5*g*t^2
                    let x = p.originX * size.width + p.velocityX * t
                    let y = p.originY * size.height + p.velocityY * t
                            + 0.5 * gravity * t * t
                    let rot = Angle(degrees: p.rotationRate * 360 * Double(t))
                    ctx.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: rot)
                        layer.opacity = alpha
                        var path = Path()
                        let half = p.size / 2
                        switch p.shape {
                        case .square:
                            path.addRect(CGRect(
                                x: -half, y: -half,
                                width: p.size, height: p.size
                            ))
                        case .circle:
                            path.addEllipse(in: CGRect(
                                x: -half, y: -half,
                                width: p.size, height: p.size
                            ))
                        }
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
            .red, .orange, .yellow, .green, .blue, .purple, .pink, .cyan
        ]
        return (0..<particleCount).map { _ in
            // Launch angle: full 360° so the burst forms a sphere.
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: speedRange)
            return Particle(
                originX: CGFloat.random(in: 0.46...0.54),
                originY: CGFloat.random(in: 0.36...0.44),
                velocityX: speed * CGFloat(cos(angle)),
                velocityY: speed * CGFloat(sin(angle)),
                rotationRate: Double.random(in: -3...3),
                color: colors.randomElement() ?? .red,
                size: CGFloat.random(in: 6...12),
                shape: Bool.random() ? .square : .circle
            )
        }
    }
}
