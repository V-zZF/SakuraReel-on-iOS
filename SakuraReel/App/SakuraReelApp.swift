import SwiftUI
import SwiftData

@main
struct SakuraReelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

private let sharedModelContainer: ModelContainer = {
    let schema = Schema([MediaItem.self])
    let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false
    )
    do {
        return try ModelContainer(for: schema, configurations: [configuration])
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}()
