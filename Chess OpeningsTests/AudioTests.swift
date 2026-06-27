import XCTest
import ChessKit
@testable import Chess_Openings

final class AudioTests: XCTestCase {

    // MARK: - filename mapping

    func test_soundeffect_filenames_match_bundle() {
        XCTAssertEqual(SoundEffect.moveSelf.fileName, "move-self")
        XCTAssertEqual(SoundEffect.moveOpponent.fileName, "move-opponent")
        XCTAssertEqual(SoundEffect.capture.fileName, "capture")
        XCTAssertEqual(SoundEffect.castle.fileName, "castle")
        XCTAssertEqual(SoundEffect.promote.fileName, "promote")
        XCTAssertEqual(SoundEffect.moveCheck.fileName, "move-check")
        XCTAssertEqual(SoundEffect.illegal.fileName, "illegal")
        XCTAssertEqual(SoundEffect.incorrect.fileName, "incorrect")
        XCTAssertEqual(SoundEffect.correct.fileName, "correct")
        XCTAssertEqual(SoundEffect.puzzleCorrect.fileName, "puzzle-correct")
        XCTAssertEqual(SoundEffect.achievement.fileName, "achievement")
        XCTAssertEqual(SoundEffect.gameStart.fileName, "game-start")
        XCTAssertEqual(SoundEffect.gameEnd.fileName, "game-end")
        XCTAssertEqual(SoundEffect.click.fileName, "click")
        XCTAssertEqual(SoundEffect.lineVictory.fileName, "result-good-2-15")
        XCTAssertEqual(SoundEffect.wrongMove.fileName, "incorrect-2-15")
    }

    /// Guard against the build forgetting to copy the new mp3s into the
    /// bundle. `SoundEffect.fileName` is just a string — without this
    /// check a typo or missing resource would only surface at runtime.
    func test_new_sound_effects_are_in_bundle() {
        XCTAssertNotNil(Bundle.main.url(forResource: "result-good-2-15", withExtension: "mp3"))
        XCTAssertNotNil(Bundle.main.url(forResource: "incorrect-2-15", withExtension: "mp3"))
    }

    // MARK: - forMove resolver

    /// helper: apply one san ply to `pos` and return (move, postPosition).
    ///
    /// Uses the SAN-parsed move (which carries `promotedPiece`/`checkState`
    /// and matches what `DrillSession` feeds into the sound classifier)
    /// rather than the `Board`-returned move, which drops the promotion
    /// flag.
    private func apply(_ san: String, to pos: Position) throws -> (Move, Position) {
        let move = try SanCodec.parse(san, in: pos)
        var board = Board(position: pos)
        guard board.move(pieceAt: move.start, to: move.end) != nil else {
            throw SanCodec.SanError.invalidSan(san)
        }
        return (move, board.position)
    }

    /// helper: apply a sequence of san plies from the start and return the
    /// position reached after all of them.
    private func position(after plies: [String]) throws -> Position {
        var pos = Position.standard
        for san in plies {
            let (_, post) = try apply(san, to: pos)
            pos = post
        }
        return pos
    }

    func test_quiet_user_move_is_moveSelf() throws {
        let pre = Position.standard
        let (move, post) = try apply("e4", to: pre)
        let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: true)
        XCTAssertEqual(sfx, .moveSelf)
    }

    func test_quiet_book_reply_is_moveOpponent() throws {
        let pre = try position(after: ["e4"])
        let (move, post) = try apply("e5", to: pre)
        let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: false)
        XCTAssertEqual(sfx, .moveOpponent)
    }

    func test_capture_overrides_moveSelf() throws {
        // 1. e4 d5 2. exd5 — white user captures on d5
        let pre = try position(after: ["e4", "d5"])
        let (move, post) = try apply("exd5", to: pre)
        let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: true)
        XCTAssertEqual(sfx, .capture)
    }

    func test_castle_short_detected() throws {
        // white castles kingside on move 4
        let pre = try position(after: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5"])
        let (move, post) = try apply("O-O", to: pre)
        let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: true)
        XCTAssertEqual(sfx, .castle)
    }

    func test_promote_detected() throws {
        // rig a position with a white pawn on a7 about to promote.
        // easiest: use FEN for position just before promotion.
        let pre = Position(fen: "8/P6k/8/8/8/8/7K/8 w - - 0 1")!
        let (move, post) = try apply("a8=Q", to: pre)
        let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: true)
        XCTAssertEqual(sfx, .promote)
    }

    func test_check_overrides_capture() throws {
        // Scholar's Mate: 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6?? 4. Qxf7#
        // Qxf7 is a capture AND delivers mate (check). Effect should be moveCheck.
        let pre = try position(after: ["e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6"])
        let (move, post) = try apply("Qxf7#", to: pre)
        let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: true)
        XCTAssertEqual(sfx, .moveCheck)
    }

    func test_check_overrides_quiet_move() throws {
        // 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6?? 4. Qxf7 is mate (captures).
        // need a pure quiet-check. use: 1. e4 d6 2. Bc4 Nf6?? — play 3. Bxf7+?
        // that's still a capture. try: 1. f3 e5 2. g4?? Qh4#  -> Qh4# is quiet + check.
        let pre = try position(after: ["f3", "e5", "g4"])
        let (move, post) = try apply("Qh4#", to: pre)
        let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: false)
        XCTAssertEqual(sfx, .moveCheck)
    }

    // MARK: - AudioService

    @MainActor
    func test_audioservice_noop_when_muted() {
        let svc = AudioService(isEnabled: { false })
        svc.play(.moveSelf)
        XCTAssertEqual(svc.lastAttemptedEffect, nil)
    }

    @MainActor
    func test_audioservice_records_last_effect_when_enabled() {
        let svc = AudioService(isEnabled: { true })
        svc.play(.capture)
        XCTAssertEqual(svc.lastAttemptedEffect, .capture)
    }

    // MARK: - armed move sound (plays on animation completion)

    /// Arming a move sound must NOT play it immediately — the whole
    /// point is to defer the sound until the board's move animation
    /// finishes, so the noise lands as the piece reaches its square.
    @MainActor
    func test_arm_does_not_play_immediately() {
        let svc = AudioService(isEnabled: { true })
        svc.arm(.capture)
        XCTAssertEqual(svc.lastAttemptedEffect, nil)
    }

    /// Flushing plays the armed effect — this is what the board's
    /// animation-completion callback drives.
    @MainActor
    func test_flushArmed_plays_the_armed_effect() {
        let svc = AudioService(isEnabled: { true })
        svc.arm(.capture)
        svc.flushArmed()
        XCTAssertEqual(svc.lastAttemptedEffect, .capture)
    }

    /// A second flush must not replay the sound — the armed slot is
    /// cleared once played, so an unrelated later animation (undo,
    /// reset) doesn't re-trigger the previous move's sound.
    @MainActor
    func test_flushArmed_clears_after_playing() {
        let svc = AudioService(isEnabled: { true })
        svc.arm(.moveSelf)
        svc.flushArmed()
        XCTAssertEqual(svc.lastAttemptedEffect, .moveSelf)

        // Play an unrelated effect, then flush again with nothing
        // armed. If the slot weren't cleared, the second flush would
        // replay moveSelf; instead lastAttemptedEffect stays on the
        // unrelated effect, proving the no-op.
        svc.play(.click)
        svc.flushArmed()
        XCTAssertEqual(svc.lastAttemptedEffect, .click)
    }

    /// Flushing with nothing armed is a silent no-op (covers
    /// animations that aren't moves, like undo/reset).
    @MainActor
    func test_flushArmed_noop_when_nothing_armed() {
        let svc = AudioService(isEnabled: { true })
        svc.flushArmed()
        XCTAssertEqual(svc.lastAttemptedEffect, nil)
    }
}
