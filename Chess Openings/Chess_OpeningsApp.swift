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

    @State private var status = AppStatus()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(status)
        }
        .modelContainer(sharedModelContainer)
    }
}
