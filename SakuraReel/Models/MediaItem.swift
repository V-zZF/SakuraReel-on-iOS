import Foundation
import SwiftData

@Model
final class MediaItem {
    var id: UUID = UUID()
    var title: String = ""
    @Attribute(.externalStorage) var poster: Data?
    var status: MediaStatus = MediaStatus.wantToWatch
    var watchYear: Int?
    var watchMonth: Int?
    var rating: Int = 0
    var review: String?
    var playURL: String?
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String,
        poster: Data? = nil,
        status: MediaStatus,
        watchYear: Int? = nil,
        watchMonth: Int? = nil,
        rating: Int = 0,
        review: String? = nil,
        playURL: String? = nil,
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.poster = poster
        self.status = status
        self.watchYear = watchYear
        self.watchMonth = watchMonth
        self.rating = max(0, min(10, rating))
        self.review = review
        self.playURL = playURL
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
