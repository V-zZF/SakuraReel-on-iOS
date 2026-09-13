import SwiftUI

/// 首页排序模式的拖动代理：只在「同年同月」组内重排，跨组时阻止移动并上报提示文案。
///
/// 分组键来自 `MediaSort.groupKey(of:)`（唯一来源），本代理不自行判断年月。
/// 拖动过程只改 `items`（HomeView 的本地草稿），不触碰磁盘；落盘由「完成」触发。
struct HomeReorderDropDelegate: DropDelegate {
    /// 当前卡片（拖动落点的目标条目）
    let targetItem: MediaItem
    /// 排序模式的草稿顺序
    @Binding var items: [MediaItem]
    /// 正在被拖动的条目 id
    @Binding var draggedItemID: UUID?
    /// 跨组被阻止时写入的提示文案（nil = 不提示）
    @Binding var blockedMessage: String?

    /// 跨年月拖动时显示的提示文案
    static let blockedText = "只能调整相同观看年月内的作品顺序。"

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedItemID,
              draggedID != targetItem.id,
              let from = items.firstIndex(where: { $0.id == draggedID }),
              let to = items.firstIndex(where: { $0.id == targetItem.id }),
              MediaSort.groupKey(of: items[from]) == MediaSort.groupKey(of: targetItem)
        else { return } // 跨组悬停：不做任何移动

        withAnimation(.easeInOut(duration: 0.2)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedItemID = nil }

        guard let draggedID = draggedItemID,
              let from = items.firstIndex(where: { $0.id == draggedID }),
              MediaSort.groupKey(of: items[from]) != MediaSort.groupKey(of: targetItem)
        else { return true }

        // 跨年月：拒绝落点并提示
        blockedMessage = Self.blockedText
        return false
    }
}
