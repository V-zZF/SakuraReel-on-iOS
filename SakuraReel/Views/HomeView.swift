import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(MediaRepository.self) private var repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedStatus: MediaStatus? = .watched
    @State private var movingToLaterStatus = true
    @State private var outgoingCategory: CategorySnapshot?
    @State private var categorySlideProgress: CGFloat = 1
    @State private var categorySlideTask: Task<Void, Never>?
    @State private var isSearchActive: Bool = false
    @State private var searchText: String = ""
    @State private var isSortMode: Bool = false
    @State private var savingOrder = false
    @State private var tmdbSettings = false
    @State private var sheetTarget: SheetTarget?
    /// 是否已 Push 进排行榜；工具栏按钮通过此状态触发导航。
    @State private var showsRankings = false
    @State private var showsTimeMachine = false
    @State private var isLaunchingTimeMachine = false
    @State private var timeMachineItems: [MediaItem] = []
    @State private var titleScale: CGFloat = 1

    /// 已确认删除、但等 Sheet 关完再落盘的条目。见 `onDelete` 处的说明
    @State private var pendingDeleteID: UUID?

    /// 排序模式的草稿顺序：拖动只改这里，点「完成」才落盘，点「✕」直接丢弃即回滚
    @State private var draftItems: [MediaItem] = []
    @State private var sortStatus: MediaStatus = .watched
    @State private var lastReorderTargetID: UUID?
    @State private var pendingReorderTargetID: UUID?
    @State private var reorderHoverTask: Task<Void, Never>?
    @State private var draggedItemID: UUID?
    /// 本次拖动开始前的草稿顺序快照，用于跨年月被拒时回滚
    @State private var dragStartSnapshot: [MediaItem] = []
    /// 跨年月拖动被阻止时的提示文案（nil = 不提示）
    @State private var blockedMessage: String?

    /// 已记住的同步文件夹名（nil = 还没选过）
    @State private var syncFolderName: String? = SyncFolder.displayName
    /// 正在读 / 写同步文件夹。云盘上的文件可能要先下载，这段时间会卡住，所以禁掉菜单入口
    @State private var synchronizer = LibrarySyncController()
    private var isSyncing: Bool { synchronizer.isRunning }
    @State private var isChoosingSyncFolder = false
    @State private var syncMessage: SyncMessage?

    /// 同步操作结束后给用户看的一句话
    private struct SyncMessage {
        let title: String
        let body: String
    }

    private struct CategorySnapshot {
        let status: MediaStatus
        let items: [MediaItem]
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
        repository.homeItems
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

    private var categorySelection: Binding<MediaStatus?> {
        Binding(
            get: { selectedStatus },
            set: { next in
                guard let next, next != selectedStatus else { return }
                let statuses = MediaStatus.allCases
                let previousIndex = statuses.firstIndex(of: selectedStatus ?? .watched) ?? 0
                let nextIndex = statuses.firstIndex(of: next) ?? 0
                movingToLaterStatus = nextIndex > previousIndex
                categorySlideTask?.cancel()
                categorySlideTask = nil
                if reduceMotion || isSearchActive || isSortMode {
                    outgoingCategory = nil
                    categorySlideProgress = 1
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        selectedStatus = next
                        isSearchActive = false
                    }
                } else {
                    if let previous = selectedStatus {
                        outgoingCategory = CategorySnapshot(
                            status: previous,
                            items: allItems.filter { $0.status == previous }
                        )
                    }
                    categorySlideProgress = 0
                    selectedStatus = next
                    categorySlideTask = Task { @MainActor in
                        // Give SwiftUI one frame to render the two pages at their start positions.
                        try? await Task.sleep(for: .milliseconds(16))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            categorySlideProgress = 1
                        }
                        try? await Task.sleep(for: .milliseconds(320))
                        guard !Task.isCancelled else { return }
                        outgoingCategory = nil
                        categorySlideTask = nil
                    }
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                let gridWidth = viewport.size.width
                let bottomInset = viewport.safeAreaInsets.bottom
                ZStack(alignment: .bottomTrailing) {
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                if isSortMode {
                                    // 排序模式：显示全部条目（无筛选），保证每个「同年同月」组都是完整的，
                                    // 完整顺序表必须覆盖全部条目，不受分类筛选影响
                                    sortGrid(availableWidth: gridWidth)
                                } else {
                                    VStack(spacing: 0) {
                                        // 分类选择器 + 搜索按钮，位于标题下方
                                        HStack(spacing: 8) {
                                            syncMenu
                                                .frame(width: 44, height: 44)
                                            CategorySegmentedControl(selectedStatus: categorySelection, isSearchActive: $isSearchActive)
                                        }
                                        .id("libraryTop")
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

                                        if isSearchActive {
                                            libraryPage(items: filteredItems, emptyStatus: nil, availableWidth: gridWidth)
                                        } else {
                                            ZStack(alignment: .top) {
                                                if let outgoingCategory {
                                                    libraryPage(
                                                        items: outgoingCategory.items,
                                                        emptyStatus: outgoingCategory.status, availableWidth: gridWidth
                                                    )
                                                    .frame(width: gridWidth > 0 ? gridWidth : nil)
                                                    .offset(x: (movingToLaterStatus ? -1 : 1) * gridWidth * categorySlideProgress)
                                                    .opacity(1 - categorySlideProgress)
                                                    .allowsHitTesting(false)
                                                }
                                                if let status = selectedStatus {
                                                    libraryPage(
                                                        items: allItems.filter { $0.status == status },
                                                        emptyStatus: status, availableWidth: gridWidth
                                                    )
                                                    .frame(width: gridWidth > 0 ? gridWidth : nil)
                                                    .offset(x: outgoingCategory == nil
                                                        ? 0
                                                        : (movingToLaterStatus ? 1 : -1) * gridWidth * (1 - categorySlideProgress))
                                                    .opacity(outgoingCategory == nil ? 1 : categorySlideProgress)
                                                    .allowsHitTesting(outgoingCategory == nil)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .top)
                                            .clipped()
                                        }
                                    }
                                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: isSearchActive)
                                }
                            }
                            .padding(.bottom, bottomInset)
                        }
                        // Keep the scroll origin below the native navigation bar.
                        // Only extend the bottom; scrollTo must never place the picker behind the title.
                        .frame(height: viewport.size.height + bottomInset)
                        .clipped()
                        // 兜底：手指在卡片之间的空隙、或最后一行下方的空白处松开时，没有任何卡片的
                        // `.onDrop` 会被触发，`draggedItemID` 就永远留着 —— 卡片会一直挂着「抬起」的透明态。
                        // 返回 false，不抢内层卡片的落点
                        .onDrop(of: [.text], isTargeted: nil) { _ in
                            cancelReorderHover()
                            lastReorderTargetID = nil
                            draggedItemID = nil
                            return false
                        }
                        .onChange(of: selectedStatus) { _, _ in
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                scrollProxy.scrollTo("libraryTop", anchor: .top)
                            }
                        }
                        .onChange(of: isSearchActive) { _, active in
                            if active { cancelCategorySlide() }
                        }
                    }
                    .frame(height: viewport.size.height, alignment: .top)

                    if !isSortMode {
                        AddButton {
                            sheetTarget = .add
                        }
                        .padding(24)
                    }
                }
                // GeometryReader owns the viewport size independently of the grid's old width.
                .frame(width: viewport.size.width, height: viewport.size.height)
            }
            .background(Constants.libraryBackground)
            .onChange(of: draggedItemID) { _, id in
                if id == nil { cancelReorderHover() }
            }
            .onDisappear { cancelReorderHover() }
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
            .sheet(item: Binding(get: { sheetTarget == nil && !tmdbSettings && !isChoosingSyncFolder ? synchronizer.conflictRequest : nil }, set: { value in
                if value == nil { synchronizer.cancelConflict() }
            })) { request in
                SyncConflictSheet(request: request) { choices in
                    synchronizer.resolve(choices, repository: repository)
                }
            }
            .onChange(of: synchronizer.isRunning) { _, running in
                if !running { syncFolderName = SyncFolder.displayName }
            }
            .onChange(of: synchronizer.message?.title) { _, _ in
                if let message = synchronizer.message {
                    syncMessage = SyncMessage(title: message.title, body: message.body)
                    synchronizer.message = nil
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSyncing && synchronizer.conflictRequest == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(synchronizer.phase).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                    .accessibilityIdentifier("syncProgress")
                }
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
                        .accessibilityLabel("取消排序")
                    } else {
                        Button {
                            enterSortMode()
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel("排序")
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("SakuraReel")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.brandTitlePink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .scaleEffect(titleScale)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.5, perform: {
                            enterTimeMachine()
                        }, onPressingChanged: { pressing in
                            guard !isSortMode, !reduceMotion else { return }
                            withAnimation(reduceMotion ? nil : (pressing
                                ? .easeOut(duration: 0.18)
                                : .spring(response: 0.3, dampingFraction: 0.48))) {
                                titleScale = pressing ? 1.08 : 1
                            }
                        })
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(isSortMode ? "排序完成后可进入时光机" : "长按进入时光机")
                        .accessibilityAction(named: Text("进入时光机")) {
                            enterTimeMachine()
                        }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSortMode {
                        Button {
                            commitSortMode()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel("完成")
                    } else {
                        Button {
                            showsRankings = true
                        } label: {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel("排行")
                    }
                }
            }
            .modifier(LibraryInteractionFeedback(
                isSorting: isSortMode, editingID: sheetTarget?.id,
                draggedID: draggedItemID, blockedMessage: blockedMessage,
                draftIDs: draftItems.map(\.id)
            ))
            .disabled(savingOrder)
            .navigationTitle("SakuraReel")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsRankings) {
                RankingsView()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .librarySheet(isPresented: $tmdbSettings) { TMDbSettingsView() }
            .librarySheet(item: $sheetTarget, onDismiss: commitPendingDelete) { target in
                switch target {
                case .add:
                    AddMediaFlowView(onSave: { try await repository.upsert($0) })
                        .environment(repository)
                case .edit(let item):
                    // Explicitly inject across the sheet hosting boundary (iPad app on Mac).
                    MediaDetailView(itemID: item.id).environment(repository)
                }
            }
            .alert("资料库文件错误", isPresented: Binding(get: { repository.lastError != nil }, set: { if !$0 { repository.lastError = nil } })) {
                Button("好的", role: .cancel) {}
            } message: { Text(repository.lastError ?? "") }
            .alert("无法移动", isPresented: isBlockedAlertPresented) {
                Button("好", role: .cancel) { blockedMessage = nil }
            } message: {
                Text(blockedMessage ?? "")
            }
        }
        .accessibilityHidden(showsTimeMachine)
        .overlay {
            if showsTimeMachine {
                TimeMachinePortal(items: timeMachineItems, rankingOrder: repository.rankingOrder, reduceMotion: reduceMotion) {
                    showsTimeMachine = false
                    timeMachineItems = []
                }
            }
        }
    }

    /// Sheet 关完之后才真正删：这时淡出才看得见。`sheetTarget` 已经是 nil，
    /// 所以只能靠 id 去库里找那一条 —— 找不到（例如中途被撤销）就当没发生过。
    private func commitPendingDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        guard let item = repository.items.first(where: { $0.id == id }) else { return }
        Task { await repository.delete(item) }
    }

    /// 把 `blockedMessage: String?` 桥接成 alert 需要的 `isPresented`
    private var isBlockedAlertPresented: Binding<Bool> {
        Binding(
            get: { blockedMessage != nil },
            set: { if !$0 { blockedMessage = nil } }
        )
    }

    // MARK: - 双向增量同步

    /// 工具栏的「···」菜单
    private var syncMenu: some View {
        Menu {
            Button("TMDb 设置", systemImage: "gearshape") { tmdbSettings = true }
                .disabled(isSyncing)
            Divider()
            Button {
                isChoosingSyncFolder = true
            } label: {
                Label(syncFolderName == nil ? "选择同步文件夹" : "更换同步文件夹", systemImage: "folder")
            }
            .accessibilityIdentifier("syncChooseFolder")
            .disabled(isSyncing)

            Divider()

            Button {
                synchronizer.start(repository: repository)
            } label: {
                Label(syncFolderName.map { "同步「\($0)」" } ?? "同步", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("syncLibrary")
            .disabled(syncFolderName == nil || isSyncing)
            if isSyncing { Text(synchronizer.phase) }
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
        .accessibilityLabel(isSyncing ? synchronizer.phase : "资料库同步")
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
                                      body: "以后会与这个文件夹双向同步，只更新变化的图片文件。")
        case .failure(let error):
            syncMessage = SyncMessage(title: "没法使用这个文件夹", body: error.localizedDescription)
        }
    }

    private var syncMessagePresented: Binding<Bool> {
        Binding(get: { syncMessage != nil }, set: { if !$0 { syncMessage = nil } })
    }

    // MARK: - 排序模式

    /// 进入排序模式：退出搜索、只加载当前分类的草稿顺序。
    ///
    /// 草稿沿用当前首页显示顺序，手动调整仅限同年月组。
    private func enterSortMode() {
        cancelCategorySlide()
        isSearchActive = false
        searchText = ""
        sortStatus = selectedStatus ?? .watched
        draftItems = repository.homeItems.filter { $0.status == sortStatus }
        lastReorderTargetID = nil
        draggedItemID = nil
        blockedMessage = nil
        isSortMode = true
    }

    /// 提交草稿顺序并退出。
    ///
    /// 只提交当前分类，仓库保留其他分类的顺序。
    private func commitSortMode() {
        guard !savingOrder else { return }
        savingOrder = true
        let ids = draftItems.map(\.id)
        let status = sortStatus
        Task {
            defer { savingOrder = false }
            do { try await repository.applyHomeReorder(ids, status: status); exitSortMode() }
            catch { repository.lastError = error.localizedDescription }
        }
    }

    /// 放弃草稿并退出：不写盘，草稿丢弃即回到进入前的顺序。
    private func cancelSortMode() {
        exitSortMode()
    }

    private func exitSortMode() {
        cancelReorderHover()
        isSortMode = false
        draftItems = []
        lastReorderTargetID = nil
        draggedItemID = nil
        dragStartSnapshot = []
        blockedMessage = nil
    }

    private func cancelReorderHover() {
        reorderHoverTask?.cancel()
        reorderHoverTask = nil
        pendingReorderTargetID = nil
    }

    private func cancelCategorySlide() {
        categorySlideTask?.cancel()
        categorySlideTask = nil
        outgoingCategory = nil
        categorySlideProgress = 1
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

    @ViewBuilder
    private func libraryPage(items: [MediaItem], emptyStatus: MediaStatus?, availableWidth: CGFloat) -> some View {
        if items.isEmpty {
            EmptyStateView(status: emptyStatus) {
                sheetTarget = .add
            }
            .padding(.top, 80)
        } else {
            gridContent(items: items, availableWidth: availableWidth)
        }
    }

    private func gridContent(items: [MediaItem], availableWidth: CGFloat) -> some View {
        AdaptiveGridLayout(availableWidth: availableWidth) {
            ForEach(items) { item in
                MediaCard(item: item, onOpen: { sheetTarget = .edit(item) })
                    .transition(.opacity)
            }
        }
    }

    private func enterTimeMachine() {
        guard !isSortMode, !isLaunchingTimeMachine, !showsTimeMachine else { return }
        isLaunchingTimeMachine = true
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.48)) {
            titleScale = 1
        }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(180)) }
            timeMachineItems = repository.items
            showsTimeMachine = true
            isLaunchingTimeMachine = false
        }
    }

    /// 排序模式网格：与正常网格共用 `AdaptiveGridLayout`（列数唯一来源），
    /// 卡片在组内可拖动重排，跨观看年月拖动由 `HomeReorderDropDelegate` 阻止。
    private func sortGrid(availableWidth: CGFloat) -> some View {
        AdaptiveGridLayout(availableWidth: availableWidth) {
            ForEach(draftItems) { item in
                MediaCard(item: item, isInteractive: false)
                    .onDrag {
                        cancelReorderHover()
                        lastReorderTargetID = nil
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
                            lastReorderTargetID: $lastReorderTargetID,
                            pendingTargetID: $pendingReorderTargetID,
                            hoverTask: $reorderHoverTask,
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
