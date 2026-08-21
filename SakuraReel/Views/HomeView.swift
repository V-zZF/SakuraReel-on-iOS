import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: MediaSort.homeDescriptors(mode: .default)) private var allItems: [MediaItem]

    @State private var selectedStatus: MediaStatus? = .watched
    @State private var isSearchActive: Bool = false
    @State private var searchText: String = ""
    @State private var isSortMode: Bool = false
    @State private var showAddSheet: Bool = false

    private var filteredItems: [MediaItem] {
        if isSearchActive && !searchText.isEmpty {
            return allItems.filter { $0.title.localizedStandardContains(searchText) }
        }
        if let status = selectedStatus {
            return allItems.filter { $0.status == status }
        }
        return allItems
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 0) {
                        // 分类选择器 + 搜索按钮，位于标题下方
                        CategorySegmentedControl(selectedStatus: $selectedStatus, isSearchActive: $isSearchActive)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        if isSearchActive {
                            searchBar
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }

                        if filteredItems.isEmpty {
                            EmptyStateView(status: isSearchActive ? nil : selectedStatus) {
                                showAddSheet = true
                            }
                            .padding(.top, 80)
                        } else {
                            gridContent
                        }
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isSearchActive)
                }

                AddButton {
                    showAddSheet = true
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSortMode {
                        Button {
                            isSortMode = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Button("排序") {
                            isSortMode = true
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("SakuraReel")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.accentPink)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSortMode {
                        Button("完成") {
                            isSortMode = false
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    } else {
                        NavigationLink(destination: RankingsView()) {
                            Text("排行")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showAddSheet) {
                Text("添加作品（Phase 3 实现）")
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索片名…", text: $searchText)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("取消") {
                isSearchActive = false
                searchText = ""
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var gridContent: some View {
        AdaptiveGridLayout {
            ForEach(filteredItems) { item in
                MediaCard(item: item)
            }
        }
    }
}

#Preview("有数据") {
    HomeView()
        .modelContainer(PreviewSampleData.container)
}

#Preview("空状态") {
    HomeView()
        .modelContainer(for: MediaItem.self, inMemory: true)
}

#Preview("iPad", traits: .landscapeLeft) {
    HomeView()
        .modelContainer(PreviewSampleData.container)
}
