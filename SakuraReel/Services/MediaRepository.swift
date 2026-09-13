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
    ///
    /// 新增时分配 `sortIndex = 全局最大 + 1`（Phase 4），保证新条目落在其观看年月组的末尾；
    /// 编辑（已存在）保留原 `sortIndex`，不因字段修改而改变组内顺序。
    /// `rankIndex` 同理保留；但若评分变了，旧的组内名次已无意义，清回 nil 让它按观看时间落到新组。
    func upsert(_ item: MediaItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            if items[index].rating != item.rating {
                updated.rankIndex = nil
            }
            items[index] = updated
        } else {
            var newItem = item
            newItem.sortIndex = (items.map(\.sortIndex).max() ?? -1) + 1
            items.append(newItem)
        }
        save()
    }

    /// 持久化某个观看年月组的手动重排（Phase 4）。
    ///
    /// `orderedGroupIDs` 须为该组条目按新顺序排列的全部 id；这些条目被重编为连续的
    /// `0…n-1` sortIndex，其它条目一律不动。写入后立即落盘。
    func applyHomeReorder(_ orderedGroupIDs: [UUID]) {
        let rank = Dictionary(uniqueKeysWithValues: orderedGroupIDs.enumerated().map { ($0.element, $0.offset) })
        items = items.map { item in
            guard let r = rank[item.id] else { return item }
            var copy = item
            copy.sortIndex = r
            return copy
        }
        save()
    }

    /// 持久化某个评分组的手动重排（Phase 5）。
    ///
    /// `orderedGroupIDs` 须为排行榜条目按新顺序排列的全部 id；这些条目按各自所属的评分组
    /// 被重编为连续的 `0…n-1` rankIndex，其它条目一律不动。写入后立即落盘。
    ///
    /// 与 `applyHomeReorder` 一样按组各自重编：评分组是排行榜的唯一分组，组间互不影响。
    func applyRankingReorder(_ orderedGroupIDs: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var rank: [UUID: Int] = [:]
        var counts: [Int: Int] = [:]
        for id in orderedGroupIDs {
            guard let item = byID[id] else { continue }
            let key = MediaSort.rankingGroupKey(of: item)
            rank[id] = counts[key, default: 0]
            counts[key, default: 0] += 1
        }
        items = items.map { item in
            guard let r = rank[item.id] else { return item }
            var copy = item
            copy.rankIndex = r
            return copy
        }
        save()
    }

    /// 删除条目，并移除对应的海报文件。
    func delete(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: posterURL(for: item.id))
        save()
    }

    // MARK: - 同步（导入 / 导出）

    /// 导入前的回滚点：把当前库文件整份另存为 `Documents/导入前备份.json`（每次覆盖）。
    ///
    /// 用 `Data.write` 而不是 `FileManager.copyItem` —— 后者在目标已存在时会抛错，
    /// 而这里要的正是「覆盖上一次的备份」。
    ///
    /// 只备份元数据，不含海报：被覆盖的海报是**同一个 id** 的海报（本 App 没有「删掉海报
    /// 但保留条目」的路径），所以拿回滚点还原之后最坏是某条的海报变成另一台设备的版本，
    /// 不会串到别的条目上。真正的完整备份是「导出到同步文件夹」这个动作本身。
    func makeImportBackup() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        do {
            try data.write(to: directoryURL.appendingPathComponent(Self.importBackupFileName), options: .atomic)
        } catch {
            print("SakuraReel: 导入前备份失败 \(error)")
        }
    }

    /// 用导入合并后的结果整体替换当前库并落盘。
    ///
    /// 合并本身在 `LibraryArchive.merge` 里（纯函数，可单测），这里只负责落盘。
    func applyImport(_ items: [MediaItem]) {
        // 被换成「没有海报」版本的条目，旧海报文件必须删掉：`loadPosterData` 是按 id 读文件的，
        // 留在盘上会在下次启动时把这个已经删掉的海报「复活」
        for item in items where item.poster == nil {
            try? FileManager.default.removeItem(at: posterURL(for: item.id))
        }
        self.items = items
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
