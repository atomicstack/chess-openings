import CoreGraphics
import Foundation

/// Pure geometry for the animated board arrow. Deliberately free of
/// SwiftUI so the routing math — especially the L-shaped knight bend —
/// can be unit-tested directly.
///
/// A "route" is the polyline the arrow follows: two points for a plain
/// move (start → end) or three for a knight move (start → corner →
/// end). Distances are measured in points along that polyline.
enum ArrowGeometry {
    /// The corner square an L-shaped knight arrow bends through, or
    /// `nil` for any non-knight move. The long leg (the two-square
    /// axis) is travelled first from the origin, then the short leg
    /// turns into the destination — e.g. b1→c3 routes b1 → b3 → c3,
    /// and b1→d2 routes b1 → d1 → d2.
    ///
    /// Files and ranks are 1...8 (a→1, h→8 / rank 1→1, rank 8→8).
    static func knightCorner(
        fromFile: Int, fromRank: Int, toFile: Int, toRank: Int
    ) -> (file: Int, rank: Int)? {
        let fileDelta = abs(toFile - fromFile)
        let rankDelta = abs(toRank - fromRank)
        if fileDelta == 1 && rankDelta == 2 {
            // rank moves two squares: travel the rank first, then file
            return (fromFile, toRank)
        } else if fileDelta == 2 && rankDelta == 1 {
            // file moves two squares: travel the file first, then rank
            return (toFile, fromRank)
        }
        return nil
    }

    static func segmentLength(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Total length of the polyline.
    static func routeLength(_ route: [CGPoint]) -> CGFloat {
        guard route.count >= 2 else { return 0 }
        return zip(route, route.dropFirst())
            .reduce(0) { $0 + segmentLength($1.0, $1.1) }
    }

    /// The point and local heading (radians) at `distance` along the
    /// route. Clamps to the final vertex (with the last segment's
    /// heading) when `distance` runs past the end.
    static func pointAtRouteDistance(
        _ route: [CGPoint], distance: CGFloat
    ) -> (point: CGPoint, angle: CGFloat)? {
        guard route.count >= 2 else { return nil }
        var consumed: CGFloat = 0
        for (a, b) in zip(route, route.dropFirst()) {
            let seg = segmentLength(a, b)
            if seg == 0 { continue }
            if distance <= consumed + seg {
                let t = max(0, min(1, (distance - consumed) / seg))
                return (lerp(a, b, t), atan2(b.y - a.y, b.x - a.x))
            }
            consumed += seg
        }
        let a = route[route.count - 2]
        let b = route[route.count - 1]
        return (b, atan2(b.y - a.y, b.x - a.x))
    }

    /// The sub-polyline of `route` covering cumulative distances
    /// `from`...`to`, with interpolated endpoints. Used to draw the
    /// growing shaft up to (but not into) the arrowhead.
    static func polyline(
        _ route: [CGPoint], from: CGFloat, to: CGFloat
    ) -> [CGPoint] {
        guard route.count >= 2, to > from else { return [] }
        var points: [CGPoint] = []
        var consumed: CGFloat = 0
        for (a, b) in zip(route, route.dropFirst()) {
            let seg = segmentLength(a, b)
            if seg == 0 { continue }
            let segFrom = consumed
            let segTo = consumed + seg
            let lo = max(from, segFrom)
            let hi = min(to, segTo)
            if hi > lo {
                let pLo = lerp(a, b, (lo - segFrom) / seg)
                let pHi = lerp(a, b, (hi - segFrom) / seg)
                if points.isEmpty || segmentLength(points[points.count - 1], pLo) > 0.001 {
                    points.append(pLo)
                }
                points.append(pHi)
            }
            consumed = segTo
        }
        return points
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
