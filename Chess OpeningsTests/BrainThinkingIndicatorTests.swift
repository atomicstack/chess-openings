import XCTest
@testable import Chess_Openings

final class BrainThinkingIndicatorTests: XCTestCase {
    private var refDate: Date {
        Date(timeIntervalSince1970: 1_000_000)
    }

    func test_invisible_when_not_thinking_and_no_start() {
        let v = BrainVisibility(
            isThinking: false, startedAt: nil,
            now: refDate, pulsePeriod: 0.6
        )
        XCTAssertFalse(v.shouldBeVisible)
    }

    func test_visible_immediately_when_thinking_starts() {
        let v = BrainVisibility(
            isThinking: true, startedAt: refDate,
            now: refDate, pulsePeriod: 0.6
        )
        XCTAssertTrue(v.shouldBeVisible)
    }

    func test_stays_visible_when_thinking_stops_inside_one_pulse() {
        let v = BrainVisibility(
            isThinking: false, startedAt: refDate,
            now: refDate.addingTimeInterval(0.1), pulsePeriod: 0.6
        )
        XCTAssertTrue(v.shouldBeVisible,
                      "min-pulse guarantee: at least one full cycle")
    }

    func test_hides_after_min_pulse_when_thinking_stopped() {
        let v = BrainVisibility(
            isThinking: false, startedAt: refDate,
            now: refDate.addingTimeInterval(0.7), pulsePeriod: 0.6
        )
        XCTAssertFalse(v.shouldBeVisible)
    }

    func test_visible_indefinitely_while_still_thinking() {
        let v = BrainVisibility(
            isThinking: true, startedAt: refDate,
            now: refDate.addingTimeInterval(5.0), pulsePeriod: 0.6
        )
        XCTAssertTrue(v.shouldBeVisible)
    }
}
