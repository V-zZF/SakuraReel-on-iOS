import SwiftUI

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .environment(MediaRepository(seedItems: PreviewSampleData.sampleItems))
}
