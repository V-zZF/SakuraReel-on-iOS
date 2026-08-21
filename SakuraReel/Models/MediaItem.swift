import Foundation

/// 影视收藏条目。纯值类型，可 Codable，用于本地 JSON 文件存储。
///
/// 存储规则：
/// - 元数据（片名、分类、年月、评分、短评、链接、排序）写入 `Documents/SakuraReelLibrary.json`
/// - `poster` 只在内存中使用，不写入 JSON；海报图片单独存为 `Documents/Posters/<id>.jpg`
struct MediaItem: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var status: MediaStatus
    var watchYear: Int?
    var watchMonth: Int?
    var rating: Int        // 0 = 未评分
    var review: String?
    var playURL: String?
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    /// 海报图片数据（JPEG）。不参与 JSON 编解码，由 MediaRepository 按 id 读写对应文件。
    var poster: Data?

    private enum CodingKeys: String, CodingKey {
        case id, title, status, watchYear, watchMonth, rating, review, playURL, sortIndex, createdAt, updatedAt
    }

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
