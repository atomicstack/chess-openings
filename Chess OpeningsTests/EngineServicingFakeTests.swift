import XCTest
import ChessKit
@testable import Chess_Openings

@MainActor
final class EngineServicingFakeTests: XCTestCase {
    func test_fake_returns_scripted_best_move() async throws {
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["e2e4", "g1f3"]
        let m1 = await fake.bestMove(
            at: .standard, skill: 10, budget: .depth(8)
        )
        XCTAssertEqual(m1?.uci, "e2e4")
        let m2 = await fake.bestMove(
            at: .standard, skill: 10, budget: .depth(8)
        )
        XCTAssertEqual(m2?.uci, "g1f3")
    }

    func test_fake_returns_scripted_evaluation() async throws {
        let fake = FakeEngineService()
        fake.scriptedEvaluations = [.cp(-450), .cp(0), .cp(100)]
        let e1 = await fake.evaluate(at: .standard, budget: .depth(8))
        let e2 = await fake.evaluate(at: .standard, budget: .depth(8))
        let e3 = await fake.evaluate(at: .standard, budget: .depth(8))
        XCTAssertEqual(e1, .cp(-450))
        XCTAssertEqual(e2, .cp(0))
        XCTAssertEqual(e3, .cp(100))
    }

    func test_fake_records_skill_for_each_bestmove_call() async {
        let fake = FakeEngineService()
        fake.scriptedBestMoves = ["a2a3"]
        _ = await fake.bestMove(at: .standard, skill: 17, budget: .depth(8))
        XCTAssertEqual(fake.lastBestMoveSkill, 17)
        XCTAssertEqual(fake.bestMoveCalls, 1)
    }

    func test_fake_returns_nil_when_script_exhausted() async {
        let fake = FakeEngineService()
        let m = await fake.bestMove(at: .standard, skill: 10, budget: .depth(8))
        XCTAssertNil(m)
    }
}
