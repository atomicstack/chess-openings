import XCTest
import SwiftData
@testable import Chess_Openings

@MainActor
final class SeedLoaderVersionTests: XCTestCase {
    func test_fresh_db_seeds_and_records_version() throws {
        let ctx = try makeContext()
        let bundle = seedBundle()
        try SeedLoader().seedIfNeeded(context: ctx, bundle: bundle)
        let settings = try ctx.fetch(FetchDescriptor<UserSettings>()).first
        XCTAssertNotNil(settings)
        XCTAssertEqual(settings?.seededVersion, currentBundledVersion())
        let count = try ctx.fetchCount(FetchDescriptor<Opening>())
        XCTAssertEqual(count, currentBundledOpeningCount())
    }

    func test_same_version_skips_reseed_and_preserves_user_lines() throws {
        let ctx = try makeContext()
        let bundle = seedBundle()
        try SeedLoader().seedIfNeeded(context: ctx, bundle: bundle)
        // insert a user line
        let userOpening = Opening(name: "homebrew", eco: nil, side: .white, rootFen: "", isSeed: false)
        let userLine = Line(name: "mine", plies: [])
        userLine.opening = userOpening
        userOpening.lines.append(userLine)
        ctx.insert(userOpening)
        try ctx.save()

        // re-run with same version
        try SeedLoader().seedIfNeeded(context: ctx, bundle: seedBundle())
        let userOpenings = try ctx.fetch(FetchDescriptor<Opening>(predicate: #Predicate { $0.isSeed == false }))
        XCTAssertEqual(userOpenings.count, 1)
    }

    func test_lower_stored_version_triggers_reseed() throws {
        let ctx = try makeContext()
        let bundle = seedBundle()
        // simulate: seed at version 0, then bundle is whatever the current shipped version is
        let s = UserSettings(seededVersion: 0)
        ctx.insert(s)
        let stale = Opening(name: "stale", eco: nil, side: .white, rootFen: "", isSeed: true)
        ctx.insert(stale)
        try ctx.save()

        try SeedLoader().seedIfNeeded(context: ctx, bundle: bundle)
        let seeded = try ctx.fetch(FetchDescriptor<Opening>(predicate: #Predicate { $0.isSeed == true }))
        XCTAssertEqual(seeded.count, currentBundledOpeningCount())
        XCTAssertFalse(seeded.contains { $0.name == "stale" })
    }

    /// Regression: prior to the stable-key upsert, every seed version
    /// bump wiped all seeded openings/lines/progress (via cascading
    /// delete) before re-importing. The user lost every learned streak
    /// they had built up — explicitly reported.
    /// Expected behaviour now: re-seed matches existing lines to the
    /// new seed via `Line.stableKey` and updates them in place,
    /// preserving the attached `LineProgress`.
    func test_reseed_preserves_line_progress_via_stable_key() throws {
        let ctx = try makeContext()
        let bundle = seedBundle()
        try SeedLoader().seedIfNeeded(context: ctx, bundle: bundle)

        // pick a seed line with a stable key and mutate its progress
        let lines = try ctx.fetch(FetchDescriptor<Line>())
        guard let line = lines.first(where: { $0.stableKey != nil }) else {
            XCTFail("no seed lines have a stableKey set"); return
        }
        let stableKey = line.stableKey
        let progress = line.mastery ?? LineProgress()
        progress.correctStreak = 7
        progress.isLearned = true
        line.mastery = progress
        try ctx.save()

        // simulate version bump by resetting the settings row, then
        // re-running the loader against the SAME bundled seed.
        let settings = try ctx.fetch(FetchDescriptor<UserSettings>()).first!
        settings.seededVersion = 0
        try ctx.save()

        try SeedLoader().seedIfNeeded(context: ctx, bundle: bundle)

        // The same stableKey must still exist with the same mastery.
        let postLines = try ctx.fetch(FetchDescriptor<Line>())
        guard let postLine = postLines.first(where: { $0.stableKey == stableKey }) else {
            XCTFail("line with stableKey '\(stableKey ?? "nil")' was deleted by re-seed"); return
        }
        XCTAssertEqual(postLine.mastery?.correctStreak, 7,
                       "correctStreak must survive re-seed")
        XCTAssertEqual(postLine.mastery?.isLearned, true,
                       "isLearned must survive re-seed")
    }

    /// One-shot migration: a Line stored under a previous seed schema
    /// has no `stableKey`. The loader must match it to the new DTO by
    /// ply-prefix (root + fork) so attached `LineProgress` survives
    /// the schema transition. Without this, the v3→v4 deploy would
    /// wipe progress a second time.
    func test_reseed_backfills_stableKey_for_legacy_lines_and_preserves_progress() throws {
        let ctx = try makeContext()
        let bundle = seedBundle()

        let url = bundle.url(forResource: "openings", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(SeedDTO.self, from: data)

        // Pick any DTO opening + line that has a stableKey
        guard let targetOpening = dto.openings.first(where: {
            $0.lines.contains(where: { $0.stableKey != nil })
        }), let targetLine = targetOpening.lines.first(where: { $0.stableKey != nil }) else {
            XCTFail("no DTO line with stableKey to migrate against"); return
        }

        // Simulate a v3-era row: same plies as the DTO line, but no
        // stableKey on the Line (and an old SAN-style name).
        let sideEnum: Side = targetOpening.side == "black" ? .black : .white
        let legacyOpening = Opening(
            name: targetOpening.name, eco: targetOpening.eco, side: sideEnum,
            rootFen: targetOpening.rootFen, openingDescription: targetOpening.description,
            isSeed: true
        )
        let legacyLine = Line(
            name: "Bc5",  // v3-style SAN name
            plies: targetLine.plies, tags: targetLine.tags,
            source: targetLine.source, stableKey: nil
        )
        let progress = LineProgress()
        progress.correctStreak = 5
        progress.isLearned = true
        legacyLine.mastery = progress
        legacyLine.opening = legacyOpening
        legacyOpening.lines.append(legacyLine)
        ctx.insert(legacyOpening)

        let s = UserSettings(seededVersion: max(0, dto.version - 1))
        ctx.insert(s)
        try ctx.save()

        try SeedLoader().seedIfNeeded(context: ctx, bundle: bundle)

        let lines = try ctx.fetch(FetchDescriptor<Line>())
        guard let matched = lines.first(where: { $0.stableKey == targetLine.stableKey }) else {
            XCTFail("legacy line not backfilled — stableKey '\(targetLine.stableKey ?? "nil")' missing")
            return
        }
        XCTAssertEqual(matched.mastery?.correctStreak, 5,
                       "progress must survive the legacy → stableKey backfill")
        XCTAssertEqual(matched.mastery?.isLearned, true)
        // The row should have been updated in place (same id), not
        // recreated alongside a wiped one. So total line count in this
        // opening matches the DTO's line count.
        let openingNow = try ctx.fetch(
            FetchDescriptor<Opening>(predicate: #Predicate { $0.isSeed == true })
        ).first(where: { $0.name == targetOpening.name })
        XCTAssertEqual(openingNow?.lines.count, targetOpening.lines.count)
    }

    private func seedBundle() -> Bundle {
        Bundle(for: Self.self).url(forResource: "openings", withExtension: "json") != nil
            ? Bundle(for: Self.self) : Bundle.main
    }
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Opening.self, Line.self, LineProgress.self, UserSettings.self])
        let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [cfg])
        return ModelContext(container)
    }
    private func currentBundledVersion() -> Int {
        let url = seedBundle().url(forResource: "openings", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(SeedDTO.self, from: data).version
    }
    private func currentBundledOpeningCount() -> Int {
        let url = seedBundle().url(forResource: "openings", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(SeedDTO.self, from: data).openings.count
    }
}
