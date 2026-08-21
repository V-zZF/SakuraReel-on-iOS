import Foundation
import SwiftData

enum HomeSortMode {
    case `default`
    case manual
}

struct MediaSort {
    static func homeDescriptors(mode: HomeSortMode) -> [SortDescriptor<MediaItem>] {
        [
            SortDescriptor(\.watchYear, order: .reverse),
            SortDescriptor(\.watchMonth, order: .reverse),
            SortDescriptor(\.sortIndex, order: .forward)
        ]
    }

    static func rankingDescriptors() -> [SortDescriptor<MediaItem>] {
        [
            SortDescriptor(\.rating, order: .reverse),
            SortDescriptor(\.watchYear, order: .reverse),
            SortDescriptor(\.watchMonth, order: .reverse),
            SortDescriptor(\.sortIndex, order: .forward)
        ]
    }

    static func homeGroupKey(year: Int?, month: Int?) -> Int {
        guard let year = year, let month = month else { return -1 }
        return year * 100 + month
    }

    static func rankingGroupKey(rating: Int) -> Int {
        return rating
    }
}
