import XCTest
@testable import Chess_Openings

final class EngineLevelTests: XCTestCase {
    func test_default_is_skill_ten() {
        XCTAssertEqual(EngineLevel.default.stockfishSkill, 10)
    }

    func test_clamps_skill_to_0_through_20() {
        XCTAssertEqual(EngineLevel(rawSkill: -3).stockfishSkill, 0)
        XCTAssertEqual(EngineLevel(rawSkill: 25).stockfishSkill, 20)
    }

    func test_opponent_search_budget_scales_with_skill() {
        XCTAssertEqual(EngineLevel(rawSkill: 0).opponentSearchBudget,
                       .depth(4))
        XCTAssertEqual(EngineLevel(rawSkill: 20).opponentSearchBudget,
                       .depth(15))
    }
}
