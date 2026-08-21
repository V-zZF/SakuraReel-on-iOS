import SwiftUI
import SwiftData

struct RankingsView: View {
    @Query(sort: [SortDescriptor<MediaItem>(\.rating, order: .reverse)]) private var items: [MediaItem]

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
        .modelContainer(for: MediaItem.self, inMemory: true)
}
