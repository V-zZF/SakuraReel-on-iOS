import SwiftUI

/// 排行榜排序模式的拖动代理：只在「同评分」组内重排，跨组时阻止移动并上报提示文案。
///
/// 分组键来自 `MediaSort.rankingGroupKey(of:)`（唯一来源），本代理不自行判断评分。
/// 拖动过程只改 `items`（RankingsView 的本地草稿），不触碰磁盘；落盘由「完成」触发。
struct RankingReorderDropDelegate: DropDelegate {
    /// 当前条目（拖动落点的目标条目）
    let targetItem: MediaItem
    /// 排序模式的草稿顺序
    @Binding var items: [MediaItem]
    /// 正在被拖动的条目 id
    @Binding var draggedItemID: UUID?
    /// 本次拖动开始前的草稿顺序快照，用于跨组被拒时回滚
    @Binding var dragStartSnapshot: [MediaItem]
    /// 跨组被阻止时写入的提示文案（nil = 不提示）
    @Binding var blockedMessage: String?
    @Binding var lastReorderTargetID: UUID?
    var reduceMotion: Bool = false

    /// 跨评分拖动时显示的提示文案（配合 alert 标题「无法移动」）
    static let blockedText = "只能调整相同评分内的作品顺序。"

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedItemID,
              draggedID != targetItem.id,
              lastReorderTargetID != targetItem.id,
              let from = items.firstIndex(where: { $0.id == draggedID }),
              let to = items.firstIndex(where: { $0.id == targetItem.id }),
              MediaSort.rankingGroupKey(of: items[from]) == MediaSort.rankingGroupKey(of: targetItem)
        else { return } // 跨组悬停：不做任何移动

        lastReorderTargetID = targetItem.id
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            MediaSort.moveWithinGroup(&items, from: from, to: to, ranking: true)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            lastReorderTargetID = nil
            draggedItemID = nil
            dragStartSnapshot = []
        }

        guard let draggedID = draggedItemID,
              let from = items.firstIndex(where: { $0.id == draggedID }),
              MediaSort.rankingGroupKey(of: items[from]) != MediaSort.rankingGroupKey(of: targetItem)
        else { return true }

        // 跨评分：拒绝落点。拖动途中经过同组条目时已经发生过重排，这里必须整体回滚，
        // 否则一次被拒绝的跨组拖动会顺带把条目挪到本组的另一处。
        items = dragStartSnapshot
        blockedMessage = Self.blockedText
        return false
    }
}
