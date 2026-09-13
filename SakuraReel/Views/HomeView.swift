import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(MediaRepository.self) private var repository

    @State private var selectedStatus: MediaStatus? = .watched
    @State private var isSearchActive: Bool = false
    @State private var searchText: String = ""
    @State private var isSortMode: Bool = false
    @State private var sheetTarget: SheetTarget?

    /// 排序模式的草稿顺序：拖动只改这里，点「完成」才落盘，点「✕」直接丢弃即回滚
    @State private var draftItems: [MediaItem] = []
    @State private var draggedItemID: UUID?
    /// 跨年月拖动被阻止时的提示文案（nil = 不提示）
    @State private var blockedMessage: String?

    /// 添加 / 编辑 Sheet 目标（nil = 关闭）
    enum SheetTarget: Identifiable {
        case add
        case edit(MediaItem)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let item): return item.id.uuidString
            }
        }
    }

    private var allItems: [MediaItem] {
        MediaSort.homeSorted(repository.items, mode: .default)
    }

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
                    if isSortMode {
                        // 排序模式：显示全部条目（无筛选），保证每个「同年同月」组都是完整的，
                        // 重排后重编 sortIndex 才不会与未显示的组内条目撞车
                        sortGrid
                    } else {
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
                                    sheetTarget = .add
                                }
                                .padding(.top, 80)
                            } else {
                                gridContent
                            }
                        }
                        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isSearchActive)
                    }
                }

                if !isSortMode {
                    AddButton {
                        sheetTarget = .add
                    }
                    .padding(24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSortMode {
                        Button {
                            cancelSortMode()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Button("排序") {
                            enterSortMode()
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
                            commitSortMode()
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
            .sheet(item: $sheetTarget) { target in
                switch target {
                case .add:
                    AddEditMediaView(
                        initialItem: nil,
                        onSave: { repository.upsert($0) },
                        onDelete: nil
                    )
                case .edit(let item):
                    AddEditMediaView(
                        initialItem: item,
                        onSave: { repository.upsert($0) },
                        onDelete: { repository.delete(item) }
                    )
                }
            }
            .alert("无法移动", isPresented: isBlockedAlertPresented) {
                Button("好", role: .cancel) { blockedMessage = nil }
            } message: {
                Text(blockedMessage ?? "")
            }
        }
    }

    /// 把 `blockedMessage: String?` 桥接成 alert 需要的 `isPresented`
    private var isBlockedAlertPresented: Binding<Bool> {
        Binding(
            get: { blockedMessage != nil },
            set: { if !$0 { blockedMessage = nil } }
        )
    }

    // MARK: - 排序模式

    /// 进入排序模式：退出搜索、加载全量草稿顺序。
    ///
    /// 草稿沿用默认排序（年月从新到旧）而非 `.manual`，因为手动顺序是按组各自重编
    /// `0…n-1` 的，全局按 `sortIndex` 排会让不同年月组交错、同组不再连续。
    private func enterSortMode() {
        isSearchActive = false
        searchText = ""
        draftItems = MediaSort.homeSorted(repository.items, mode: .default)
        draggedItemID = nil
        blockedMessage = nil
        isSortMode = true
    }

    /// 提交草稿顺序并退出。
    ///
    /// 传入全部条目 id：`applyHomeReorder` 会对每个观看年月组各自重编为连续的
    /// `0…n-1`，组内相对顺序即拖动后的顺序，跨组互不影响。
    private func commitSortMode() {
        repository.applyHomeReorder(draftItems.map(\.id))
        exitSortMode()
    }

    /// 放弃草稿并退出：不写盘，草稿丢弃即回到进入前的顺序。
    private func cancelSortMode() {
        exitSortMode()
    }

    private func exitSortMode() {
        isSortMode = false
        draftItems = []
        draggedItemID = nil
        blockedMessage = nil
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
                    .onTapGesture { sheetTarget = .edit(item) }
            }
        }
    }

    /// 排序模式网格：与正常网格共用 `AdaptiveGridLayout`（列数唯一来源），
    /// 卡片在组内可拖动重排，跨观看年月拖动由 `HomeReorderDropDelegate` 阻止。
    private var sortGrid: some View {
        AdaptiveGridLayout {
            ForEach(draftItems) { item in
                MediaCard(item: item, isInteractive: false)
                    .onDrag {
                        draggedItemID = item.id
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: HomeReorderDropDelegate(
                            targetItem: item,
                            items: $draftItems,
                            draggedItemID: $draggedItemID,
                            blockedMessage: $blockedMessage
                        )
                    )
            }
        }
    }
}

#Preview("有数据") {
    HomeView()
        .environment(MediaRepository(seedItems: PreviewSampleData.sampleItems))
}

#Preview("空状态") {
    HomeView()
        .environment(MediaRepository(seedItems: []))
}

#Preview("iPad", traits: .landscapeLeft) {
    HomeView()
        .environment(MediaRepository(seedItems: PreviewSampleData.sampleItems))
}
