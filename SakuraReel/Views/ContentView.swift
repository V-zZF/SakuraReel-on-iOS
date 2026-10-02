import SwiftUI

struct ContentView: View {
    @Environment(MediaRepository.self) private var repository
    var body: some View {
        HomeView()
            .disabled(repository.isLoading)
            .overlay { if repository.isLoading { ProgressView("正在读取资料库") } }
    }
}

#Preview {
    ContentView()
        .environment(MediaRepository(seedItems: PreviewSampleData.sampleItems))
}
