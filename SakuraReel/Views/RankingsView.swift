import SwiftUI

struct RankingsView: View {
    @Environment(MediaRepository.self) private var repository

    private var items: [MediaItem] {
        MediaSort.rankingSorted(repository.items)
    }

    var body: some View {
        NavigationStack {
            List(items) { item in
                Text(item.title)
            }
            .navigationTitle("评分排行榜")
        }
    }
}

#Preview {
    RankingsView()
        .environment(MediaRepository(seedItems: PreviewSampleData.sampleItems))
}
