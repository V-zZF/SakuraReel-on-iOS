import Foundation

enum HomeSortMode {
    case `default`
    case manual
}

/// 排序与拖动分组逻辑唯一来源。
/// 基于数组排序（本地 JSON 文件存储，不使用 SwiftData SortDescriptor）。
enum MediaSort {
    /// 首页排序：观看年份从新到旧 → 观看月份从新到旧 → sortIndex。
    /// 无观看年月（想看）的条目排在最末。
    static func homeSorted(_ items: [MediaItem], mode: HomeSortMode) -> [MediaItem] {
        switch mode {
        case .default:
            return items.sorted {
                if $0.watchYear != $1.watchYear { return ($0.watchYear ?? -1) > ($1.watchYear ?? -1) }
                if $0.watchMonth != $1.watchMonth { return ($0.watchMonth ?? -1) > ($1.watchMonth ?? -1) }
                return $0.sortIndex < $1.sortIndex
            }
        case .manual:
            return items.sorted { $0.sortIndex < $1.sortIndex }
        }
    }

    /// 排行榜排序：评分从高到低 → rankIndex → 观看时间从新到旧 → sortIndex。
    ///
    /// `rankIndex` 只在被手动排过的评分组里有值。整库都没手动排过时全部为 nil（按 0 比较），
    /// 比较器逐级落到观看时间与 `sortIndex`，即「评分 > 观看时间 > sortIndex」的默认规则。
    static func rankingSorted(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted(by: rankingAreInIncreasingOrder)
    }

    /// 排行榜比较器的本体。
    ///
    /// 单独提出来是为了让**导入后的索引修正**复用同一份规则（`LibraryArchive.normalizeIndices`
    /// 要按当前显示顺序重编撞车的组），而不是在那边再抄一遍评分/时间/序号的比较顺序。
    /// 提取前后 `rankingSorted` 的行为逐字不变。
    static func rankingAreInIncreasingOrder(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
        if (lhs.rankIndex ?? 0) != (rhs.rankIndex ?? 0) { return (lhs.rankIndex ?? 0) < (rhs.rankIndex ?? 0) }
        if lhs.watchYear != rhs.watchYear { return (lhs.watchYear ?? -1) > (rhs.watchYear ?? -1) }
        if lhs.watchMonth != rhs.watchMonth { return (lhs.watchMonth ?? -1) > (rhs.watchMonth ?? -1) }
        return lhs.sortIndex < rhs.sortIndex
    }

    /// 首页拖动分组：相同观看年月为一组。
    static func homeGroupKey(year: Int?, month: Int?) -> Int {
        guard let year = year, let month = month else { return -1 }
        return year * 100 + month
    }

    /// 首页拖动分组的条目便捷版（Phase 4 拖动逻辑使用）。
    static func groupKey(of item: MediaItem) -> Int {
        homeGroupKey(year: item.watchYear, month: item.watchMonth)
    }

    /// 排行榜拖动分组：相同评分为一组。
    static func rankingGroupKey(rating: Int) -> Int {
        rating
    }

    /// 排行榜拖动分组的条目便捷版（Phase 5 拖动逻辑使用）。
    static func rankingGroupKey(of item: MediaItem) -> Int {
        rankingGroupKey(rating: item.rating)
    }
}
