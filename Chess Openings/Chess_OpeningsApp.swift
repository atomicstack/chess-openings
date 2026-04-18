import SwiftUI
import SwiftData

@main
struct Chess_OpeningsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Opening.self,
            Line.self,
            LineProgress.self,
            UserSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("could not create model container: \(error)")
        }
    }()

    init() {
        let context = sharedModelContainer.mainContext
        do {
            try SeedLoader().seedIfEmpty(context: context)
        } catch {
            print("seed failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
