import SwiftUI

struct SquareView: View {
    let isLight: Bool
    let highlights: Set<HighlightKind>

    /// Wall-clock instant the pulse highlight first appeared. Anchoring
    /// the LFO to this stamp (instead of `timeIntervalSinceReferenceDate`)
    /// means every press of "hint" starts the animation from phase 0, so
    /// the user always sees the same fade-in identical to the previous
    /// time — not a free-running oscillator caught mid-cycle.
    @State private var pulseStartedAt: Date?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lineWidth = side / 10
            ZStack {
                Rectangle().fill(isLight ? Color(white: 139.0 / 255.0) : Color(white: 105.0 / 255.0))
                ForEach(rectHighlights, id: \.self) { h in
                    Rectangle().fill(h.overlayColor)
                }
                if highlights.contains(.hintFromPulse), let start = pulseStartedAt {
                    // Blue-selection overlay that fades in and out: the
                    // square pulses between its base grey and the same
                    // shade `.selected` uses, then back. Time is measured
                    // from `pulseStartedAt`, so phase 0 == enable moment.
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSince(start)
                        let phase = (t.truncatingRemainder(dividingBy: 1.8)) / 1.8
                        // smoothstep-style ease via 0.5 - 0.5*cos(2π·phase)
                        // → 0 at phase 0, peaks at 0.5, back to 0 at 1.
                        let amp = 0.5 - 0.5 * cos(2 * .pi * phase)
                        Rectangle()
                            .fill(Color.blue.opacity(0.55 * amp))
                    }
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
        .onChange(of: highlights.contains(.hintFromPulse), initial: true) { _, isOn in
            // Anchor (or clear) the LFO start stamp on every transition,
            // so a re-enable after a pause resets phase to 0 rather than
            // resuming where it left off.
            pulseStartedAt = isOn ? Date() : nil
        }
    }

    private var rectHighlights: [HighlightKind] {
        highlights.filter { $0 != .captureTarget && $0 != .hintFromPulse }
    }
}
