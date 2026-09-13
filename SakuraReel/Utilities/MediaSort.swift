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

    /// 排行榜排序：评分从高到低 → 观看时间从新到旧 → sortIndex。
    static func rankingSorted(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted {
            if $0.rating != $1.rating { return $0.rating > $1.rating }
            if $0.watchYear != $1.watchYear { return ($0.watchYear ?? -1) > ($1.watchYear ?? -1) }
            if $0.watchMonth != $1.watchMonth { return ($0.watchMonth ?? -1) > ($1.watchMonth ?? -1) }
            return $0.sortIndex < $1.sortIndex
        }
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
}
