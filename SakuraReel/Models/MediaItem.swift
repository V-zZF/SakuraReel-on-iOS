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
    /// 首页手动顺序：所属「观看年月」组内的序号，由 `MediaRepository.applyHomeReorder` 重编。
    var sortIndex: Int
    /// 排行榜手动顺序：所属「评分」组内的序号，由 `MediaRepository.applyRankingReorder` 重编。
    ///
    /// `nil` = 该评分组从未手动排过，比较时按 0 处理，排序退化为 评分 → 观看时间 → `sortIndex`。
    /// 用可选类型而非 `Int = 0`：合成的 `init(from:)` 不会对缺失的 key 取属性默认值，
    /// 非可选属性会让旧库文件直接解码失败；可选属性走 `decodeIfPresent`，旧文件自然得到 `nil`。
    var rankIndex: Int?
    var createdAt: Date
    var updatedAt: Date

    /// 海报图片数据（JPEG）。不参与 JSON 编解码，由 MediaRepository 按 id 读写对应文件。
    var poster: Data?

    private enum CodingKeys: String, CodingKey {
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
        self.rankIndex = rankIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
