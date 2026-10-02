import Foundation

/// 影视收藏条目。纯值类型，可 Codable，用于本地 JSON 文件存储。
///
/// 存储规则：
/// - 元数据（片名、分类、年月、评分、短评、链接、排序）写入 `Documents/SakuraReelLibrary.json`
/// - `poster` 只在内存中使用，不写入 JSON；海报图片单独存为 `Documents/Posters/<id>.jpg`
struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var status: MediaStatus
    var watchYear: Int?
    var watchMonth: Int?
    var rating: Int        // 0 = 未评分
    var review: String?
    var playURL: String?
    /// 旧版首页组内索引；新快照读取旧数组时用于迁移顺序。
    var sortIndex: Int
    /// 旧版排行榜组内索引；保留为可选值以兼容缺失此字段的旧文件。
    var rankIndex: Int?
    var createdAt: Date
    var updatedAt: Date

    /// 海报图片数据（JPEG）。不参与 JSON 编解码，由 MediaRepository 按 id 读写对应文件。
    var poster: Data?

    var source: MediaSource?
    var metadata: MediaMetadata?
    /// Permanent attachments; like poster, bytes live outside JSON.
    var backdrop: Data?
    var logo: Data?

    private enum CodingKeys: String, CodingKey {
        case source, metadata
        case id, title, status, watchYear, watchMonth, rating, review, playURL, sortIndex, rankIndex, createdAt, updatedAt
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
        rankIndex: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        source: MediaSource? = nil,
        metadata: MediaMetadata? = nil,
        backdrop: Data? = nil,
        logo: Data? = nil
    ) {
        self.source = source
        self.metadata = metadata
        self.backdrop = backdrop
        self.logo = logo
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
        self.rankIndex = rankIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
