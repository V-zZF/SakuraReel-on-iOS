import Foundation
import Observation

/// 本地文件存储仓库（替代原 SwiftData + CloudKit）。
///
/// 数据保存在 App 沙盒的 Documents 目录，并在「文件」App 中可见
/// （我的 iPhone > SakuraReel，需 Info.plist 开启 `UIFileSharingEnabled`）：
/// - `SakuraReelLibrary.json`：所有条目的元数据（片名、分类、年月、评分、短评、链接、排序）
/// - `Posters/`：海报图片，按 `<条目 id>.jpg` 命名
///
/// 不接入 iCloud / CloudKit，数据只存在本机。
@MainActor
@Observable
final class MediaRepository {
    static let libraryFileName = "SakuraReelLibrary.json"
    static let postersDirectoryName = "Posters"

    private(set) var items: [MediaItem] = []

    private let directoryURL: URL

    private var libraryURL: URL {
        directoryURL.appendingPathComponent(Self.libraryFileName)
    }

    private var postersDirectoryURL: URL {
        directoryURL.appendingPathComponent(Self.postersDirectoryName)
    }

    /// - Parameter seedItems: 预览 / 测试用。传非 nil 时直接使用该数组，不读写磁盘；传 nil 时从 Documents 加载。
    init(seedItems: [MediaItem]? = nil) {
        directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let seedItems {
            items = seedItems
        } else {
            load()
        }
    }

    // MARK: - 读取

    func load() {
        try? FileManager.default.createDirectory(at: postersDirectoryURL, withIntermediateDirectories: true)

        guard let data = try? Data(contentsOf: libraryURL),
              let decoded = try? Self.decoder.decode([MediaItem].self, from: data) else {
            // 首次启动：创建空的库文件，让用户能在「文件」App 中看到数据文件
            items = []
            save()
            return
        }

        items = decoded.map { item in
            var copy = item
            copy.poster = loadPosterData(for: item.id)
            return copy
        }
    }

    // MARK: - 写入

    func save() {
        savePosters()
        do {
            let data = try Self.encoder.encode(items)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            print("SakuraReel: 保存库文件失败 \(error)")
        }
    }

    // MARK: - CRUD（Phase 3 使用）

    /// 新增或更新一个条目，并落盘。
    func upsert(_ item: MediaItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        save()
    }

    /// 删除条目，并移除对应的海报文件。
    func delete(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: posterURL(for: item.id))
        save()
    }

    // MARK: - 海报文件

    func posterURL(for id: UUID) -> URL {
        postersDirectoryURL.appendingPathComponent("\(id.uuidString).jpg")
    }

    private func loadPosterData(for id: UUID) -> Data? {
        try? Data(contentsOf: posterURL(for: id))
    }

    private func savePosters() {
        for item in items {
            if let poster = item.poster {
                try? poster.write(to: posterURL(for: item.id), options: .atomic)
            }
        }
    }

    // MARK: - 编解码

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
