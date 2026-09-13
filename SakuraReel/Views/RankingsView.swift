import SwiftUI
import UniformTypeIdentifiers

/// 评分排行榜。由首页工具栏的「排行」Push 进入，复用首页的 `NavigationStack`，不自建栈。
struct RankingsView: View {
    @Environment(MediaRepository.self) private var repository
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var isSortMode: Bool = false
    @State private var sheetTarget: SheetTarget?

    /// 排序模式的草稿顺序：拖动只改这里，点「完成」才落盘，点「✕」直接丢弃即回滚
    @State private var draftItems: [MediaItem] = []
    @State private var draggedItemID: UUID?
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

    /// 排行榜顺序：评分 → rankIndex → 观看时间 → sortIndex
    private var rankedItems: [MediaItem] {
        MediaSort.rankingSorted(repository.items)
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
        .background(Color(.systemGroupedBackground))
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
                    Button("排序") {
                        enterSortMode()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                }
            }
        }
        .sheet(item: $sheetTarget) { target in
            switch target {
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
        return ScrollView {
            // ScrollView 会把内容按 leading 摆放，**只给固定宽度并不会居中** ——
            // 两侧各垫一个 Spacer 才是真居中；iPhone 上 listWidth 等于全宽，Spacer 自动收成 0
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                LazyVStack(spacing: metrics.gap) {
                    ForEach(displayItems) { item in
                        row(item, rank: ranks[item.id] ?? 0, cardHeight: metrics.cardHeight)
                    }
                }
                .padding(metrics.listPadding)
                .frame(width: metrics.listWidth)
                Spacer(minLength: 0)
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

    @ViewBuilder
    private func row(_ item: MediaItem, rank: Int, cardHeight: CGFloat) -> some View {
        if isSortMode {
            RankingRow(rank: rank, item: item, cardHeight: cardHeight)
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
                        blockedMessage: $blockedMessage
                    )
                )
        } else {
            RankingRow(rank: rank, item: item, cardHeight: cardHeight)
                .contentShape(Rectangle())
                .onTapGesture { sheetTarget = .edit(item) }
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
    /// 草稿沿用当前**显示顺序**（`rankingSorted`），保证每个评分组都是连续的 ——
    /// 落盘时按评分组各自重编 `rankIndex` 才不会与其它组交错。
    private func enterSortMode() {
        draftItems = MediaSort.rankingSorted(repository.items)
        draggedItemID = nil
        blockedMessage = nil
        isSortMode = true
    }

    /// 提交草稿顺序并退出。
    ///
    /// 传入全部条目 id：`applyRankingReorder` 会对每个评分组各自重编为连续的
    /// `0…n-1`，组内相对顺序即拖动后的顺序，跨组互不影响。
    private func commitSortMode() {
        repository.applyRankingReorder(draftItems.map(\.id))
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
