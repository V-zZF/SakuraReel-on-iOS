import Foundation

enum MediaSort {
    static func homeSorted(_ items: [MediaItem], order: [UUID]) -> [MediaItem] {
        let positions = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return items.sorted {
            if $0.personal.watchedAt != $1.personal.watchedAt { return ($0.personal.watchedAt ?? YearMonth(year: 0, month: 0)) > ($1.personal.watchedAt ?? YearMonth(year: 0, month: 0)) }
            if positions[$0.id] != positions[$1.id] { return positions[$0.id, default: Int.max] < positions[$1.id, default: Int.max] }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    static func rankingSorted(_ items: [MediaItem], order: [UUID]) -> [MediaItem] {
        let positions = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return items.sorted {
            if $0.rating != $1.rating { return $0.rating > $1.rating }
            if positions[$0.id] != positions[$1.id] { return positions[$0.id, default: Int.max] < positions[$1.id, default: Int.max] }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    static func rankingDefaultSorted(_ items: [MediaItem], homeOrder: [UUID]) -> [MediaItem] {
        let home = homeSorted(items, order: homeOrder)
        let positions = Dictionary(home.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return items.sorted { $0.rating != $1.rating ? $0.rating > $1.rating : positions[$0.id, default: 0] < positions[$1.id, default: 0] }
    }
    static func rankingSorted(_ items: [MediaItem]) -> [MediaItem] { rankingDefaultSorted(items, homeOrder: items.map(\.id)) }
    static func homeGroupKey(year: Int?, month: Int?) -> Int { guard let year, let month else { return -1 }; return year * 100 + month }
    static func groupKey(of item: MediaItem) -> Int { homeGroupKey(year: item.watchYear, month: item.watchMonth) }
    static func rankingGroupKey(rating: Int) -> Int { rating }
    static func rankingGroupKey(of item: MediaItem) -> Int { item.rating }
}
