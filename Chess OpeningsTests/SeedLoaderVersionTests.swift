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
        XCTAssertEqual(count, 16)
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
        XCTAssertEqual(seeded.count, 16)
        XCTAssertFalse(seeded.contains { $0.name == "stale" })
    }

    func test_reseed_wipes_line_progress_from_old_seed() throws {
        let ctx = try makeContext()
        let bundle = seedBundle()
        try SeedLoader().seedIfNeeded(context: ctx, bundle: bundle)

        // pick any seed line and mutate its progress to non-default
        let lines = try ctx.fetch(FetchDescriptor<Line>())
        guard let line = lines.first else { XCTFail("no seed lines"); return }
        let progress = line.mastery ?? LineProgress()
        progress.correctStreak = 7
        line.mastery = progress
        try ctx.save()

        let progressCountBefore = try ctx.fetchCount(FetchDescriptor<LineProgress>())
        XCTAssertGreaterThan(progressCountBefore, 0)

        // simulate version bump by resetting the settings row
        let settings = try ctx.fetch(FetchDescriptor<UserSettings>()).first!
        settings.seededVersion = 0
        try ctx.save()

        try SeedLoader().seedIfNeeded(context: ctx, bundle: bundle)

        // all progress rows should now be fresh (correctStreak == 0 for every row)
        let progressAfter = try ctx.fetch(FetchDescriptor<LineProgress>())
        XCTAssertFalse(progressAfter.contains { $0.correctStreak == 7 },
                       "expected the mutated progress row to be cascaded away on reseed")
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
}
