import Foundation

/// 时光机的分组与展示顺序。只依赖模型，供模型测试直接编译。
enum TimeMachineMoments {
    struct Quarter: Hashable, Comparable {
        let year: Int
        let number: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.year == rhs.year ? lhs.number < rhs.number : lhs.year < rhs.year
        }

        var season: String {
            switch number {
            case 1: "冬"
            case 2: "春"
            case 3: "夏"
            default: "秋"
            }
        }

        var monthRange: String {
            switch number {
            case 1: "1–3 月"
            case 2: "4–6 月"
            case 3: "7–9 月"
            default: "10–12 月"
            }
        }

        var title: String { "\(year) 年\(season)" }
    }

    struct Moment: Identifiable {
        let quarter: Quarter
        /// 排行榜顺序，第一个是季度代表封面。
        let rankedItems: [MediaItem]

        var id: Quarter { quarter }
        var representative: MediaItem { rankedItems[0] }
        var count: Int { rankedItems.count }
    }

    static func quarter(for item: MediaItem) -> Quarter? {
        guard item.status == .watched,
              let year = item.watchYear,
              let month = item.watchMonth,
              (1...12).contains(month) else { return nil }
        return Quarter(year: year, number: (month - 1) / 3 + 1)
    }

    static func moments(from items: [MediaItem], rankingOrder: [UUID]? = nil) -> [Moment] {
        let grouped = Dictionary(grouping: items.compactMap { item -> (Quarter, MediaItem)? in
            guard let quarter = quarter(for: item) else { return nil }
            return (quarter, item)
        }, by: { $0.0 })

        return grouped.keys.sorted(by: >).map { quarter in
            Moment(
                quarter: quarter,
                rankedItems: rankingOrder.map { MediaSort.rankingSorted(grouped[quarter, default: []].map(\.1), order: $0) }
                    ?? MediaSort.rankingSorted(grouped[quarter, default: []].map(\.1))
            )
        }
    }

    /// 默认回到去年的当前季度；若该季度为空，向更早的季度寻找，最后才回退到最近的新季度。
    static func openingQuarter(in moments: [Moment], today: Date, calendar: Calendar = .current) -> Quarter? {
        let target = Quarter(
            year: calendar.component(.year, from: today) - 1,
            number: (calendar.component(.month, from: today) - 1) / 3 + 1
        )
        return moments.first(where: { $0.quarter <= target })?.quarter ?? moments.last?.quarter
    }

    /// 输入按优先级排列；输出为实际从左到右的空间位置。
    /// 1 居中，2 在左，3 在右，4 在更左，依此类推。
    static func centerOut<T>(_ items: [T]) -> [T] {
        guard let first = items.first else { return [] }
        var left: [T] = []
        var right: [T] = []
        for (index, item) in items.enumerated() where index > 0 {
            if index.isMultiple(of: 2) {
                right.append(item)
            } else {
                left.insert(item, at: 0)
            }
        }
        return left + [first] + right
    }
}
