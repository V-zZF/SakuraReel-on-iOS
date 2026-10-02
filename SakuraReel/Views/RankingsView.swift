import SwiftUI
import UniformTypeIdentifiers

/// 评分排行榜。由首页工具栏的「排行」Push 进入，复用首页的 `NavigationStack`，不自建栈。
struct RankingsView: View {
    @Environment(MediaRepository.self) private var repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var isSortMode: Bool = false
    @State private var savingOrder = false
    @State private var sheetTarget: SheetTarget?
    @State private var hasEntered = false

    /// 排序模式的草稿顺序：拖动只改这里，点「完成」才落盘，点「✕」直接丢弃即回滚
    @State private var draftItems: [MediaItem] = []
    @State private var draggedItemID: UUID?
    /// 已确认删除、但等 Sheet 关完再落盘的条目。见 `onDelete` 处的说明
    @State private var pendingDeleteID: UUID?
    /// 本次拖动开始前的草稿顺序快照，用于跨评分被拒时回滚
    @State private var dragStartSnapshot: [MediaItem] = []
    /// 跨评分拖动被阻止时的提示文案（nil = 不提示）
    @State private var blockedMessage: String?

    /// 编辑 Sheet 目标（nil = 关闭）
    enum SheetTarget: Identifiable {
        case edit(MediaItem)

        var id: String {
            switch self {
            case .edit(let item): return item.id.uuidString
            }
        }
    }

    /// 排行榜顺序：评分 → 手动评分组，未手动组走年月与首页顺序
    private var rankedItems: [MediaItem] {
        repository.rankingItems
    }

    private var displayItems: [MediaItem] {
        isSortMode ? draftItems : rankedItems
    }

    var body: some View {
        VStack(spacing: 0) {
            // 排序模式隐藏摘要行，对应首页排序模式隐藏分类胶囊与 FAB
            if !isSortMode {
                summaryRow
            }

            if displayItems.isEmpty {
                emptyState
            } else {
                // 卡片大小由「一屏几张」摊分得出，所以得先量出列表的可用区域。
                // GeometryReader 只包住列表，量到的就是扣掉导航栏与摘要行之后的净高。
                GeometryReader { geometry in
                    rankingList(metrics: RankingMetrics(availableSize: geometry.size, isPad: isPad))
                }
            }
        }
        .background(Constants.libraryBackground)
        .modifier(LibraryInteractionFeedback(
                isSorting: isSortMode, editingID: sheetTarget?.id,
                draggedID: draggedItemID, blockedMessage: blockedMessage,
                draftIDs: draftItems.map(\.id)
            ))
            .disabled(savingOrder)
            .navigationTitle("评分排行榜")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(isSortMode)
        .toolbar {
            if isSortMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        cancelSortMode()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if isSortMode {
                    Button("完成") {
                        commitSortMode()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                } else {
                    Button {
                        enterSortMode()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text("排序")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                }
            }
        }
        .sheet(item: $sheetTarget, onDismiss: commitPendingDelete) { target in
            switch target {
            case .edit(let item):
                MediaDetailView(itemID: item.id).environment(repository)
            }
        }
        .alert("无法移动", isPresented: isBlockedAlertPresented) {
            Button("好", role: .cancel) { blockedMessage = nil }
        } message: {
            Text(blockedMessage ?? "")
        }
        .task {
            guard !hasEntered else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
            hasEntered = true
        }
    }

    /// Sheet 关完之后才真正删：这时淡出才看得见。`sheetTarget` 已经是 nil，
    /// 所以只能靠 id 去库里找那一条 —— 找不到就当没发生过。
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

    // MARK: - 第二行摘要

    /// 共 N 部（全部条目） / 平均 N 分（仅统计已评分）
    private var summaryRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Text("共")
                Text("\(repository.items.count)")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("部")
            }
            HStack(spacing: 4) {
                Text("平均")
                Text(averageText)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("分")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // 三个 Text 合成一句读给 VoiceOver；同时给 UI 测试一个稳定的取值点
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("共 \(repository.items.count) 部 平均 \(averageText) 分")
        .accessibilityIdentifier("rankingSummary")
    }

    /// 平均分只算已评分条目；一条都没有时显示占位符
    private var averageText: String {
        let rated = repository.items.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return "—" }
        let total = rated.reduce(0) { $0 + $1.rating }
        return String(format: "%.1f", Double(total) / Double(rated.count))
    }

    // MARK: - 列表

    /// iPad：与 `AdaptiveGridLayout` 同一套判定（iPhone 横屏的竖 size class 也是 compact）。
    /// 半屏宽的一列只在 iPad 上出现 —— 那是屏幕宽度的一半并居中，不是把卡片压窄。
    private var isPad: Bool {
        horizontalSizeClass == .regular && verticalSizeClass != .compact
    }

    private func rankingList(metrics: RankingMetrics) -> some View {
        let ranks = rankByID
        let visibleRows = max(0, Int(ceil(
            max(metrics.availableHeight - metrics.listPadding, 0) / (metrics.cardHeight + metrics.gap)
        )))
        return ScrollView {
            // ScrollView 会把内容按 leading 摆放，**只给固定宽度并不会居中** ——
            // 两侧各垫一个 Spacer 才是真居中；iPhone 上 listWidth 等于全宽，Spacer 自动收成 0
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                LazyVStack(spacing: metrics.gap) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        // 没有 transition 的话，删除时这一行是「瞬间消失」，其余行再补位
                        row(item, rank: ranks[item.id] ?? 0, cardHeight: metrics.cardHeight)
                            .modifier(RankingEntrance(
                                index: index,
                                enabled: !isSortMode && index < visibleRows,
                                hasEntered: hasEntered
                            ))
                            .transition(.opacity)
                    }
                }
                .padding(metrics.listPadding)
                .frame(width: metrics.listWidth)
                Spacer(minLength: 0)
            }
            // 兜底：手指在行与行之间、或列表下方空白处松开时，没有任何行的 `.onDrop` 会触发，
            // `draggedItemID` 就永远留着，那一行会一直挂着「抬起」的透明态。
            // 返回 false，不抢内层行的落点
            .onDrop(of: [.text], isTargeted: nil) { _ in
                draggedItemID = nil
                return false
            }
        }
    }

    /// 排名按当前显示顺序动态计算，不用数组下标做 identity —— 拖动重排时 identity 必须跟着条目走
    private var rankByID: [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (offset, item) in displayItems.enumerated() {
            result[item.id] = offset + 1
        }
        return result
    }

    /// 整行的 VoiceOver 朗读文本。
    ///
    /// 不写这一句的话，正常模式下整行是一个 Button，系统会把 `# 序号 / 片名 / 年月 / 评分`
    /// 拼成一串碎片读出来。写成一整句更像系统列表该有的样子。
    private func rowAccessibilityLabel(rank: Int, item: MediaItem) -> String {
        var parts = ["第 \(rank) 名", item.title]
        if let year = item.watchYear, let month = item.watchMonth {
            parts.append("\(year) 年 \(month) 月观看")
        } else {
            parts.append("未设置观看年月")
        }
        parts.append(item.rating > 0 ? "\(item.rating) 分" : "未评分")
        return parts.joined(separator: "，")
    }

    @ViewBuilder
    private func row(_ item: MediaItem, rank: Int, cardHeight: CGFloat) -> some View {
        if isSortMode {
            RankingRow(
                rank: rank,
                item: item,
                cardHeight: cardHeight,
                titleBaseFontSize: isPad ? 15 : 12
            )
                // 排序模式下整行不是 Button，不写这一句就会把 `# / 序号 / 片名 / 年月 / 评分`
                // 拆成五个元素逐个朗读。与正常模式合成同一句话，两种模式读起来才一致；
                // identifier 同时给 UI 测试一个与元素类型无关的定位点
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowAccessibilityLabel(rank: rank, item: item))
                .accessibilityIdentifier(item.title)
                .onDrag {
                    dragStartSnapshot = draftItems
                    draggedItemID = item.id
                    return NSItemProvider(object: item.id.uuidString as NSString)
                }
                .onDrop(
                    of: [.text],
                    delegate: RankingReorderDropDelegate(
                        targetItem: item,
                        items: $draftItems,
                        draggedItemID: $draggedItemID,
                        dragStartSnapshot: $dragStartSnapshot,
                        blockedMessage: $blockedMessage,
                        reduceMotion: reduceMotion
                    )
                )
                // 抬起态：源行留在原位变淡。**必须挂在 `.onDrag` 之外** ——
                // 拖影是 `.onDrag` 那一层的快照，挂在里面会把「变淡」一起烤进拖影
                .opacity(draggedItemID == item.id ? Constants.draggedCardOpacity : 1)
        } else {
            Button { sheetTarget = .edit(item) } label: {
                RankingRow(
                    rank: rank,
                    item: item,
                    cardHeight: cardHeight,
                    titleBaseFontSize: isPad ? 15 : 12
                )
                    .contentShape(Rectangle())
            }
            .buttonStyle(LibraryPressStyle())
            .accessibilityLabel(rowAccessibilityLabel(rank: rank, item: item))
            .accessibilityHint("编辑")
            // 与排序模式同名：两种模式下「整行」都是同一个定位点，与元素类型无关
            .accessibilityIdentifier(item.title)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有作品", systemImage: "film.stack")
        } description: {
            Text("先回首页添加作品，这里会按评分排出名次。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 排序模式

    /// 进入排序模式：加载全量草稿顺序。
    ///
    /// 草稿沿用当前显示顺序，保证每个评分组连续。
    private func enterSortMode() {
        draftItems = repository.rankingItems
        draggedItemID = nil
        blockedMessage = nil
        isSortMode = true
    }

    /// 提交草稿顺序并退出。
    ///
    /// 传入全部条目 id，覆盖排行榜完整顺序。
    private func commitSortMode() {
        guard !savingOrder else { return }
        savingOrder = true
        let ids = draftItems.map(\.id)
        Task {
            defer { savingOrder = false }
            do { try await repository.applyRankingReorder(ids); exitSortMode() }
            catch { blockedMessage = error.localizedDescription }
        }
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
}

#Preview("有数据") {
    NavigationStack {
        RankingsView()
    }
    .environment(MediaRepository(seedItems: PreviewSampleData.sampleItems))
}

#Preview("空状态") {
    NavigationStack {
        RankingsView()
    }
    .environment(MediaRepository(seedItems: []))
}
