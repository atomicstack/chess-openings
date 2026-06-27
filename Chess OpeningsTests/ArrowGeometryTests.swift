import XCTest
import CoreGraphics
@testable import Chess_Openings

final class ArrowGeometryTests: XCTestCase {

    // MARK: - L-shaped knight corner

    func test_knightCorner_b1_c3_travels_rank_first() {
        // b1 (file 2, rank 1) → c3 (file 3, rank 3): rank moves two,
        // so the long leg is vertical → corner b3 (file 2, rank 3).
        let corner = ArrowGeometry.knightCorner(
            fromFile: 2, fromRank: 1, toFile: 3, toRank: 3
        )
        XCTAssertEqual(corner?.file, 2)
        XCTAssertEqual(corner?.rank, 3)
    }

    func test_knightCorner_g1_f3_travels_rank_first() {
        // g1 (7,1) → f3 (6,3): corner g3 (7,3).
        let corner = ArrowGeometry.knightCorner(
            fromFile: 7, fromRank: 1, toFile: 6, toRank: 3
        )
        XCTAssertEqual(corner?.file, 7)
        XCTAssertEqual(corner?.rank, 3)
    }

    func test_knightCorner_b1_d2_travels_file_first() {
        // b1 (2,1) → d2 (4,2): file moves two, so the long leg is
        // horizontal → corner d1 (file 4, rank 1).
        let corner = ArrowGeometry.knightCorner(
            fromFile: 2, fromRank: 1, toFile: 4, toRank: 2
        )
        XCTAssertEqual(corner?.file, 4)
        XCTAssertEqual(corner?.rank, 1)
    }

    func test_knightCorner_nil_for_straight_move() {
        XCTAssertNil(ArrowGeometry.knightCorner(
            fromFile: 5, fromRank: 4, toFile: 5, toRank: 5
        ))
    }

    func test_knightCorner_nil_for_diagonal_move() {
        // a1 → b2 is a bishop step, not a knight move.
        XCTAssertNil(ArrowGeometry.knightCorner(
            fromFile: 1, fromRank: 1, toFile: 2, toRank: 2
        ))
    }

    func test_knightCorner_nil_for_long_diagonal() {
        XCTAssertNil(ArrowGeometry.knightCorner(
            fromFile: 1, fromRank: 1, toFile: 8, toRank: 8
        ))
    }

    // MARK: - route length

    func test_routeLength_straight() {
        let route = [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4)]
        XCTAssertEqual(ArrowGeometry.routeLength(route), 5, accuracy: 0.0001)
    }

    func test_routeLength_L_shape() {
        // (0,0) → (0,3) → (4,3): legs of 3 and 4 → 7 total.
        let route = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 3)]
        XCTAssertEqual(ArrowGeometry.routeLength(route), 7, accuracy: 0.0001)
    }

    // MARK: - point + heading along the route

    func test_pointAtRouteDistance_on_first_leg() {
        let route = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 3)]
        let r = ArrowGeometry.pointAtRouteDistance(route, distance: 3)
        XCTAssertEqual(r?.point.x ?? .nan, 0, accuracy: 0.0001)
        XCTAssertEqual(r?.point.y ?? .nan, 3, accuracy: 0.0001)
        // heading of the first (vertical) leg
        XCTAssertEqual(r?.angle ?? .nan, .pi / 2, accuracy: 0.0001)
    }

    func test_pointAtRouteDistance_on_second_leg_turns_heading() {
        let route = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 3)]
        let r = ArrowGeometry.pointAtRouteDistance(route, distance: 5)
        // 3 along the first leg + 2 into the second leg → (2, 3)
        XCTAssertEqual(r?.point.x ?? .nan, 2, accuracy: 0.0001)
        XCTAssertEqual(r?.point.y ?? .nan, 3, accuracy: 0.0001)
        // heading now along the horizontal leg
        XCTAssertEqual(r?.angle ?? .nan, 0, accuracy: 0.0001)
    }

    func test_pointAtRouteDistance_clamps_past_end() {
        let route = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 3)]
        let r = ArrowGeometry.pointAtRouteDistance(route, distance: 100)
        XCTAssertEqual(r?.point.x ?? .nan, 4, accuracy: 0.0001)
        XCTAssertEqual(r?.point.y ?? .nan, 3, accuracy: 0.0001)
    }

    // MARK: - growing-shaft sub-polyline

    func test_polyline_within_first_leg() {
        let route = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 3)]
        let line = ArrowGeometry.polyline(route, from: 0, to: 2)
        XCTAssertEqual(line.count, 2)
        XCTAssertEqual(line.first?.y ?? .nan, 0, accuracy: 0.0001)
        XCTAssertEqual(line.last?.y ?? .nan, 2, accuracy: 0.0001)
    }

    func test_polyline_spans_the_corner() {
        let route = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 3)]
        let line = ArrowGeometry.polyline(route, from: 0, to: 5)
        // start, the corner vertex, and the interpolated end on leg two
        XCTAssertEqual(line.count, 3)
        XCTAssertEqual(line[1].x, 0, accuracy: 0.0001)
        XCTAssertEqual(line[1].y, 3, accuracy: 0.0001)
        XCTAssertEqual(line[2].x, 2, accuracy: 0.0001)
        XCTAssertEqual(line[2].y, 3, accuracy: 0.0001)
    }

    func test_polyline_empty_when_to_not_past_from() {
        let route = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3)]
        XCTAssertTrue(ArrowGeometry.polyline(route, from: 2, to: 2).isEmpty)
    }
}
