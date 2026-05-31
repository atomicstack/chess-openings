import XCTest
@testable import Chess_Openings

final class SearchBudgetTests: XCTestCase {
    func test_depth_budget_renders_as_depth_int() {
        let b = SearchBudget.depth(12)
        switch b {
        case .depth(let d): XCTAssertEqual(d, 12)
        case .movetimeMs:   XCTFail("expected .depth")
        }
    }

    func test_movetime_budget_renders_as_milliseconds() {
        let b = SearchBudget.movetimeMs(500)
        switch b {
        case .movetimeMs(let ms): XCTAssertEqual(ms, 500)
        case .depth:              XCTFail("expected .movetimeMs")
        }
    }
}
