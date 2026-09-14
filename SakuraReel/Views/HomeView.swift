import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(MediaRepository.self) private var repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedStatus: MediaStatus? = .watched
    @State private var isSearchActive: Bool = false
    @State private var searchText: String = ""
    @State private var isSortMode: Bool = false
    @State private var sheetTarget: SheetTarget?
    /// 是否已 Push 进排行榜。用「按钮 + 编程式跳转」而不是 NavigationLink：
    /// 工具栏里的 NavigationLink 会少一圈内边距，胶囊宽度和左侧「排序」对不齐
    @State private var showsRankings = false

    /// 网格容器的可用宽度（含两侧留白）。`0` = 还没量到。
    /// 量在这里而不是 `AdaptiveGridLayout` 里：`onPreferenceChange` 的闭包是 `@Sendable`，
    /// 而 `AdaptiveGridLayout` 存了一个非 `@Sendable` 的 `content` 闭包，捕获它会过不了 Swift 6 隔离检查
    @State private var gridWidth: CGFloat = 0

    /// 已确认删除、但等 Sheet 关完再落盘的条目。见 `onDelete` 处的说明
    @State private var pendingDeleteID: UUID?

    /// 排序模式的草稿顺序：拖动只改这里，点「完成」才落盘，点「✕」直接丢弃即回滚
    @State private var draftItems: [MediaItem] = []
    @State private var draggedItemID: UUID?
    /// 本次拖动开始前的草稿顺序快照，用于跨年月被拒时回滚
    @State private var dragStartSnapshot: [MediaItem] = []
    /// 跨年月拖动被阻止时的提示文案（nil = 不提示）
    @State private var blockedMessage: String?

    /// 已记住的同步文件夹名（nil = 还没选过）
    @State private var syncFolderName: String? = SyncFolder.displayName
    /// 正在读 / 写同步文件夹。云盘上的文件可能要先下载，这段时间会卡住，所以禁掉菜单入口
    @State private var isSyncing = false
    @State private var isChoosingSyncFolder = false
    /// 待确认的导入：合并结果已经算好，等用户点「导入」才写盘（nil = 无）
    @State private var pendingImport: PendingImport?
    /// 同步的结果 / 失败提示（nil = 不提示）
    @State private var syncMessage: SyncMessage?

    /// 合并结果已算好、等确认的一次导入
    private struct PendingImport {
        let items: [MediaItem]
        let summary: ImportSummary
    }

    /// 同步操作结束后给用户看的一句话
    private struct SyncMessage {
        let title: String
        let body: String
    }

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
                            HStack(spacing: 8) {
                                syncMenu
                                    .frame(width: 44, height: 44)
                                CategorySegmentedControl(selectedStatus: $selectedStatus, isSearchActive: $isSearchActive)
                            }
                            .frame(maxWidth: .infinity)
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
                        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: isSearchActive)
                    }
                }
                // 兜底：手指在卡片之间的空隙、或最后一行下方的空白处松开时，没有任何卡片的
                // `.onDrop` 会被触发，`draggedItemID` 就永远留着 —— 卡片会一直挂着「抬起」的透明态。
                // 返回 false，不抢内层卡片的落点
                .onDrop(of: [.text], isTargeted: nil) { _ in
                    draggedItemID = nil
                    return false
                }

                if !isSortMode {
                    AddButton {
                        sheetTarget = .add
                    }
                    .padding(24)
                }
            }
            .background {
                // 量网格容器的宽度，交给 GridColumns 决定列数（iPad 分栏变窄时自动减列）
                GeometryReader { proxy in
                    Color.clear.preference(key: GridWidthPreferenceKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(GridWidthPreferenceKey.self) { gridWidth = $0 }
            .background(Constants.libraryBackground)
            .sensoryFeedback(.selection, trigger: selectedStatus)
            .sensoryFeedback(.selection, trigger: isSearchActive)
            // 同步相关的弹窗挂在这一层，与 NavigationStack 上那个「无法移动」分属不同节点，
            // 免得两个 presentation 抢同一条通道
            .fileImporter(
                isPresented: $isChoosingSyncFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderSelection(result)
            }
            .alert(
                "确认导入",
                isPresented: pendingImportPresented,
                presenting: pendingImport
            ) { pending in
                Button("导入") { commitImport(pending) }
                Button("取消", role: .cancel) {}
            } message: { pending in
                Text(pending.summary.description + "\n\n本机独有的作品不会被删除。")
            }
            .alert(syncMessage?.title ?? "", isPresented: syncMessagePresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(syncMessage?.body ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // 导航栏两侧各保留一个操作，文件菜单移到分类行。
                    // 这里不再套 HStack 容器：当初套它是为了让同一 placement 上的多个
                    // ToolbarItem 顺序可控，菜单移走后只剩一个，容器已是多余
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
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.accentPink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSortMode {
                        Button("完成") {
                            commitSortMode()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    } else {
                        // 必须是 Button 而不是 NavigationLink：工具栏里的 NavigationLink
                        // 每侧比 Button 少 6pt 内边距，胶囊会比左边的「排序」窄一圈（实测 142px vs 178px）
                        Button("排行") {
                            showsRankings = true
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    }
                }
            }
            .modifier(LibraryInteractionFeedback(
                isSorting: isSortMode, editingID: sheetTarget?.id,
                draggedID: draggedItemID, blockedMessage: blockedMessage,
                draftIDs: draftItems.map(\.id)
            ))
            .navigationTitle("SakuraReel")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsRankings) {
                RankingsView()
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $sheetTarget, onDismiss: commitPendingDelete) { target in
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
                        // 删除只记下 id，真正的落盘与淡出留到 Sheet 关完之后 ——
                        // 在这里直接删的话，0.25s 的淡出全程被 Sheet 的消失动画盖住，等于没有
                        onDelete: { pendingDeleteID = item.id }
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

    /// Sheet 关完之后才真正删：这时淡出才看得见。`sheetTarget` 已经是 nil，
    /// 所以只能靠 id 去库里找那一条 —— 找不到（例如中途被撤销）就当没发生过。
    private func commitPendingDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        guard let item = repository.items.first(where: { $0.id == id }) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            repository.delete(item)
        }
    }

    /// 把 `blockedMessage: String?` 桥接成 alert 需要的 `isPresented`
    private var isBlockedAlertPresented: Binding<Bool> {
        Binding(
            get: { blockedMessage != nil },
            set: { if !$0 { blockedMessage = nil } }
        )
    }

    // MARK: - 同步（导出 / 导入）

    /// 工具栏的「···」菜单
    private var syncMenu: some View {
        Menu {
            Button {
                isChoosingSyncFolder = true
            } label: {
                Label(syncFolderName == nil ? "选择同步文件夹" : "更换同步文件夹", systemImage: "folder")
            }
            .accessibilityIdentifier("syncChooseFolder")

            Divider()

            Button {
                exportLibrary()
            } label: {
                Label(exportTitle, systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("syncExport")
            .disabled(syncFolderName == nil || isSyncing)

            Button {
                prepareImport()
            } label: {
                Label(importTitle, systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("syncImport")
            .disabled(syncFolderName == nil || isSyncing)
        } label: {
            if isSyncing {
                ProgressView()
            } else {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(Constants.accentPink)
            }
        }
        .tint(Constants.accentPink)
        .accessibilityIdentifier("syncMenu")
        .accessibilityLabel("资料库文件")
    }

    /// 菜单里带上文件夹名，让用户能确认导出 / 导入的到底是哪儿
    private var exportTitle: String {
        guard let syncFolderName else { return "导出到此文件夹" }
        return "导出到「\(syncFolderName)」"
    }

    private var importTitle: String {
        guard let syncFolderName else { return "从此文件夹导入" }
        return "从「\(syncFolderName)」导入"
    }

    /// 用户在系统选择器里选好文件夹。
    ///
    /// 授权只在回调存续期间有效，所以 bookmark 必须在这个 scope **内**建 —— 离开回调再建会失败。
    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folder = urls.first else { return }
            let didStart = folder.startAccessingSecurityScopedResource()
            defer { if didStart { folder.stopAccessingSecurityScopedResource() } }
            SyncFolder.remember(folder)
            syncFolderName = SyncFolder.displayName
            syncMessage = SyncMessage(title: "已记住同步文件夹",
                                      body: "以后「导出」「导入」用的都是这个文件夹。")
        case .failure(let error):
            syncMessage = SyncMessage(title: "没法使用这个文件夹", body: error.localizedDescription)
        }
    }

    /// 本机 → 同步文件夹，全量覆盖。
    private func exportLibrary() {
        guard !isSyncing else { return }
        isSyncing = true
        let items = repository.items
        Task {
            do {
                try await SyncFolder.withAccess { folder in
                    // 云盘上的文件可能要等系统下载，协调读写会阻塞 —— 别占主线程
                    try await Task.detached(priority: .userInitiated) {
                        try LibraryArchive.export(items, to: folder)
                    }.value
                }
                syncMessage = SyncMessage(
                    title: "导出完成",
                    body: "已把 \(items.count) 部作品写进「\(SyncFolder.displayName ?? "")」。"
                )
            } catch {
                syncMessage = SyncMessage(title: "导出失败", body: error.localizedDescription)
            }
            syncFolderName = SyncFolder.displayName
            isSyncing = false
        }
    }

    /// 同步文件夹 → 本机：先算出合并结果让用户确认会改什么，再写盘。
    private func prepareImport() {
        guard !isSyncing else { return }
        isSyncing = true
        let local = repository.items
        Task {
            do {
                let incoming = try await SyncFolder.withAccess { folder in
                    try await Task.detached(priority: .userInitiated) {
                        try LibraryArchive.read(from: folder)
                    }.value
                }
                let (merged, summary) = LibraryArchive.merge(incoming: incoming, into: local)
                if summary.changed == 0 {
                    syncMessage = SyncMessage(
                        title: "没有需要导入的内容",
                        body: "文件夹里的 \(incoming.count) 部作品，本机都已有同样新或更新的版本。\n\n\(summary.description)"
                    )
                } else {
                    pendingImport = PendingImport(items: merged, summary: summary)
                }
            } catch {
                syncMessage = SyncMessage(title: "导入失败", body: error.localizedDescription)
            }
            syncFolderName = SyncFolder.displayName
            isSyncing = false
        }
    }

    /// 确认之后才真正写盘。写之前先留一个回滚点。
    private func commitImport(_ pending: PendingImport) {
        repository.makeImportBackup()
        repository.applyImport(pending.items)
        let message = SyncMessage(title: "导入完成", body: pending.summary.description)
        // 确认弹窗正在关闭，同一个 runloop 里再挂一个 alert 会被丢掉，等它关完再说
        Task { syncMessage = message }
    }

    private var syncMessagePresented: Binding<Bool> {
        Binding(get: { syncMessage != nil }, set: { if !$0 { syncMessage = nil } })
    }

    private var pendingImportPresented: Binding<Bool> {
        Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })
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
        dragStartSnapshot = []
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
        AdaptiveGridLayout(availableWidth: gridWidth) {
            ForEach(filteredItems) { item in
                MediaCard(item: item, onOpen: { sheetTarget = .edit(item) })
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selectedStatus)
    }

    /// 排序模式网格：与正常网格共用 `AdaptiveGridLayout`（列数唯一来源），
    /// 卡片在组内可拖动重排，跨观看年月拖动由 `HomeReorderDropDelegate` 阻止。
    private var sortGrid: some View {
        AdaptiveGridLayout(availableWidth: gridWidth) {
            ForEach(draftItems) { item in
                MediaCard(item: item, isInteractive: false)
                    .onDrag {
                        dragStartSnapshot = draftItems
                        draggedItemID = item.id
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: HomeReorderDropDelegate(
                            targetItem: item,
                            items: $draftItems,
                            draggedItemID: $draggedItemID,
                            dragStartSnapshot: $dragStartSnapshot,
                            blockedMessage: $blockedMessage,
                            reduceMotion: reduceMotion
                        )
                    )
                    // 抬起态：源卡片留在原位变淡，系统的拖影跟着手指走。
                    // **必须挂在 `.onDrag` 之外** —— 拖影是 `.onDrag` 那一层的快照，
                    // 挂在里面会把「变淡」一起烤进拖影
                    .opacity(draggedItemID == item.id ? Constants.draggedCardOpacity : 1)
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
