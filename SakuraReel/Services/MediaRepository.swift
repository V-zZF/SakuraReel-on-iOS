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
    /// 命名约定与编解码配置都放在 `LibraryArchive` / `LibraryFiles` 里与本机库文件共用 ——
    /// 导出的同步文件必须和本机库文件格式完全一致，两处各写一份迟早会漂移。
    static let libraryFileName = LibraryFiles.libraryFileName
    static let postersDirectoryName = LibraryFiles.postersDirectoryName

    /// 导入前的回滚点（只保留一份，每次导入覆盖）
    static let importBackupFileName = "导入前备份.json"

    private(set) var items: [MediaItem] = []
    private(set) var homeOrder: [UUID] = []
    private(set) var rankingOrder: [UUID] = []

    var snapshot: LibrarySnapshot { LibrarySnapshot(items: items, homeOrder: homeOrder, rankingOrder: rankingOrder) }
    var homeItems: [MediaItem] { MediaSort.homeSorted(items, order: homeOrder) }
    var rankingItems: [MediaItem] { MediaSort.rankingSorted(items, order: rankingOrder) }

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
            let initial = LibrarySnapshot.legacy(seedItems)
            items = initial.items
            homeOrder = initial.homeOrder
            rankingOrder = initial.rankingOrder
        } else {
            load()
        }
    }

    // MARK: - 读取

    func load() {
        try? FileManager.default.createDirectory(at: postersDirectoryURL, withIntermediateDirectories: true)

        guard let data = try? Data(contentsOf: libraryURL),
              let decoded = try? LibrarySnapshot.decode(data) else {
            // 首次启动：创建空的库文件，让用户能在「文件」App 中看到数据文件
            items = []
            save()
            return
        }

        homeOrder = decoded.homeOrder
        rankingOrder = decoded.rankingOrder
        items = decoded.items.map { item in
            var copy = item
            copy.poster = loadPosterData(for: item.id)
            return copy
        }
        if (try? Self.decoder.decode([MediaItem].self, from: data)) != nil {
            save() // migrate the legacy array to the snapshot format on first load
        }
    }

    // MARK: - 写入

    func save() {
        savePosters()
        do {
            let data = try snapshot.encoded()
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            print("SakuraReel: 保存库文件失败 \(error)")
        }
    }

    // MARK: - CRUD（Phase 3 使用）

    /// 新增或更新一个条目，并落盘。
    ///
    /// New entries and entries moved to another date/rating group are inserted into
    /// that group by the legacy default sort. Existing order elsewhere is preserved.
    func upsert(_ item: MediaItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            if items[index].rating != item.rating {
                updated.rankIndex = nil
            }
            let old = items[index]
            items[index] = updated
            if MediaSort.groupKey(of: old) != MediaSort.groupKey(of: updated) {
                homeOrder.removeAll { $0 == updated.id }
            }
            if old.rating != updated.rating {
                rankingOrder.removeAll { $0 == updated.id }
            }
        } else {
            var newItem = item
            newItem.sortIndex = (items.map(\.sortIndex).max() ?? -1) + 1
            items.append(newItem)
        }
        repairOrders()
        save()
    }

    private func repairOrders() {
        let repaired = snapshot
        homeOrder = repaired.homeOrder
        rankingOrder = repaired.rankingOrder
    }

    /// Persist the complete home order independently of item timestamps.
    func applyHomeReorder(_ orderedIDs: [UUID]) {
        homeOrder = orderedIDs
        repairOrders()
        save()
    }

    /// Persist the complete ranking order independently of content timestamps.
    func applyRankingReorder(_ orderedIDs: [UUID]) {
        rankingOrder = orderedIDs
        repairOrders()
        save()
    }

    /// 删除条目，并移除对应的海报文件。
    func delete(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        homeOrder.removeAll { $0 == item.id }
        rankingOrder.removeAll { $0 == item.id }
        try? FileManager.default.removeItem(at: posterURL(for: item.id))
        save()
    }

    // MARK: - 同步（导入 / 导出）

    /// 导入前的回滚点：把当前库文件整份另存为 `Documents/导入前备份.json`（每次覆盖）。
    ///
    /// 用 `Data.write` 而不是 `FileManager.copyItem` —— 后者在目标已存在时会抛错，
    /// 而这里要的正是「覆盖上一次的备份」。
    ///
    /// 只备份元数据，不含海报。导入覆盖或删除的海报无法通过此文件恢复。
    func makeImportBackup() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        do {
            try data.write(to: directoryURL.appendingPathComponent(Self.importBackupFileName), options: .atomic)
        } catch {
            print("SakuraReel: 导入前备份失败 \(error)")
        }
    }

    /// Replace the complete local snapshot, including order and poster membership.
    func applyImport(_ incoming: LibrarySnapshot) {
        let incomingIDs = Set(incoming.items.filter { $0.poster != nil }.map(\.id))
        let existing = (try? FileManager.default.contentsOfDirectory(at: postersDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        for url in existing where url.pathExtension.lowercased() == "jpg" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), !incomingIDs.contains(id) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
        items = incoming.items
        homeOrder = incoming.homeOrder
        rankingOrder = incoming.rankingOrder
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

    private static var encoder: JSONEncoder { LibraryCoding.encoder }

    private static var decoder: JSONDecoder { LibraryCoding.decoder }
}
