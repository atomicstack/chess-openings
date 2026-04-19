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
        XCTAssertEqual(settings?.seededVersion, currentBundledVersion(bundle: bundle))
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
    private func currentBundledVersion(bundle: Bundle) -> Int {
        let b = seedBundle()
        let url = b.url(forResource: "openings", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(SeedDTO.self, from: data).version
    }
}
