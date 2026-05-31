import XCTest
@testable import Chess_Openings

final class MoveQualityTests: XCTestCase {
    // classification thresholds (centipawn drop from user's POV):
    //   best        drop < 5
    //   excellent   drop < 20
    //   good        drop < 50
    //   inaccuracy  drop < 100
    //   mistake     drop < 300
    //   blunder     drop >= 300
    // miss          best eval >= +200 cp (or mate>0) AND drop > 300

    func test_best_when_drop_under_five() {
        let q = MoveQuality.classify(bestEvalCp: 50, actualEvalCp: 48,
                                     bestEvalIsWinning: false)
        XCTAssertEqual(q, .best)
    }

    func test_excellent_when_drop_under_twenty() {
        let q = MoveQuality.classify(bestEvalCp: 50, actualEvalCp: 35,
                                     bestEvalIsWinning: false)
        XCTAssertEqual(q, .excellent)
    }

    func test_good_when_drop_under_fifty() {
        let q = MoveQuality.classify(bestEvalCp: 100, actualEvalCp: 70,
                                     bestEvalIsWinning: false)
        XCTAssertEqual(q, .good)
    }

    func test_inaccuracy_when_drop_under_hundred() {
        let q = MoveQuality.classify(bestEvalCp: 100, actualEvalCp: 30,
                                     bestEvalIsWinning: false)
        XCTAssertEqual(q, .inaccuracy)
    }

    func test_mistake_when_drop_under_three_hundred() {
        let q = MoveQuality.classify(bestEvalCp: 200, actualEvalCp: 50,
                                     bestEvalIsWinning: false)
        XCTAssertEqual(q, .mistake)
    }

    func test_blunder_when_drop_at_or_above_three_hundred() {
        let q = MoveQuality.classify(bestEvalCp: 0, actualEvalCp: -500,
                                     bestEvalIsWinning: false)
        XCTAssertEqual(q, .blunder)
    }

    func test_miss_when_winning_eval_is_squandered() {
        let q = MoveQuality.classify(bestEvalCp: 500, actualEvalCp: 50,
                                     bestEvalIsWinning: true)
        XCTAssertEqual(q, .miss)
    }

    func test_blunder_when_losing_eval_made_worse() {
        // user was already losing — bigger drop is just a blunder, not a miss
        let q = MoveQuality.classify(bestEvalCp: -300, actualEvalCp: -800,
                                     bestEvalIsWinning: false)
        XCTAssertEqual(q, .blunder)
    }

    // clampedCp helper — turns mate scores into ±5000 cp
    func test_clampedCp_cp_passes_through() {
        XCTAssertEqual(EngineEvaluation.cp(42).clampedCp, 42)
        XCTAssertEqual(EngineEvaluation.cp(-1500).clampedCp, -1500)
    }

    func test_clampedCp_mate_positive_clamps_to_five_thousand() {
        XCTAssertEqual(EngineEvaluation.mate(in: 1).clampedCp, 5000)
        XCTAssertEqual(EngineEvaluation.mate(in: 7).clampedCp, 5000)
    }

    func test_clampedCp_mate_negative_clamps_to_minus_five_thousand() {
        XCTAssertEqual(EngineEvaluation.mate(in: -1).clampedCp, -5000)
        XCTAssertEqual(EngineEvaluation.mate(in: -10).clampedCp, -5000)
    }

    // edge: exactly 5 cp drop is no longer "best" (drop < 5 is best, drop >= 5 is excellent)
    func test_drop_exactly_five_is_excellent_not_best() {
        let q = MoveQuality.classify(bestEvalCp: 100, actualEvalCp: 95,
                                     bestEvalIsWinning: false)
        XCTAssertEqual(q, .excellent)
    }

    // brilliant category — chess.com-style sacrifice detection
    func test_brilliant_when_candidate_and_drop_is_minimal() {
        let q = MoveQuality.classify(
            bestEvalCp: 50, actualEvalCp: 48,
            bestEvalIsWinning: false,
            isBrilliantCandidate: true
        )
        XCTAssertEqual(q, .brilliant)
    }

    func test_brilliant_supersedes_best_when_candidate() {
        // exactly 0 drop with candidate flag — would be .best otherwise
        let q = MoveQuality.classify(
            bestEvalCp: 100, actualEvalCp: 100,
            bestEvalIsWinning: false,
            isBrilliantCandidate: true
        )
        XCTAssertEqual(q, .brilliant)
    }

    func test_brilliant_only_fires_with_low_drop() {
        // candidate flag set but drop is too large — falls through to
        // the standard classifier. drop=50 (100 -> 50) lands in the
        // ..<100 bucket, so the answer is .inaccuracy.
        let q = MoveQuality.classify(
            bestEvalCp: 100, actualEvalCp: 50,
            bestEvalIsWinning: false,
            isBrilliantCandidate: true
        )
        XCTAssertEqual(q, .inaccuracy)
    }

    func test_brilliant_not_fired_without_candidate_flag() {
        let q = MoveQuality.classify(
            bestEvalCp: 50, actualEvalCp: 48,
            bestEvalIsWinning: false,
            isBrilliantCandidate: false
        )
        XCTAssertEqual(q, .best)
    }
}
