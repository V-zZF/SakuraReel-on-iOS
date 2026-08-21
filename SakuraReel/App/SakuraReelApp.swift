import SwiftUI

@main
struct SakuraReelApp: App {
    @State private var repository = MediaRepository()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(repository)
        }
    }
}
