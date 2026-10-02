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

    var lastError: String?
    private var loadFailed = false
    private let isPreview: Bool
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
    init(seedItems: [MediaItem]? = nil, directory: URL? = nil) {
        isPreview = seedItems != nil
        directoryURL = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
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
        do {
            try LibraryArchive.recoverPendingCommits(in: directoryURL)
            guard FileManager.default.fileExists(atPath: libraryURL.path) else {
                items = []; homeOrder = []; rankingOrder = []; loadFailed = false
                save(); return
            }
            let data = try Data(contentsOf: libraryURL)
            let decoded = try LibraryArchive.read(from: directoryURL)
            homeOrder = decoded.homeOrder; rankingOrder = decoded.rankingOrder; items = decoded.items
            loadFailed = false; lastError = nil
            if (try? Self.decoder.decode([MediaItem].self, from: data)) != nil { save() }
        } catch {
            loadFailed = true
            lastError = String(localized: "资料库读取失败，原文件已保留。请从完整备份恢复。")
        }
    }

    // MARK: - 写入

    func save() {
        do { try persist(snapshot) } catch { lastError = error.localizedDescription }
    }

    private func persist(_ snapshot: LibrarySnapshot, replacingUnreadable: Bool = false) throws {
        if loadFailed && !replacingUnreadable { throw LibraryArchiveError.unreadableLibraryFile }
        guard !isPreview else { return }
        try LibraryArchive.commit(snapshot, to: directoryURL)
        lastError = nil
    }

    func duplicate(for source: MediaSource, excluding id: UUID? = nil) -> MediaItem? {
        items.first { $0.id != id && $0.source?.identity == source.identity }
    }

    // MARK: - CRUD（Phase 3 使用）

    /// 新增或更新一个条目，并落盘。
    ///
    /// New entries and entries moved to another date/rating group are inserted into
    /// that group by the legacy default sort. Existing order elsewhere is preserved.
    func upsert(_ item: MediaItem) throws {
        if let source = item.source, duplicate(for: source, excluding: item.id) != nil {
            throw RepositoryError.duplicate
        }
        let oldSnapshot = snapshot
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
        do { try persist(snapshot) }
        catch {
            items = oldSnapshot.items; homeOrder = oldSnapshot.homeOrder; rankingOrder = oldSnapshot.rankingOrder
            throw error
        }
    }

    private func repairOrders() {
        let repaired = snapshot
        homeOrder = repaired.homeOrder
        rankingOrder = repaired.rankingOrder
    }

    /// Persist the complete home order independently of item timestamps.
    func applyHomeReorder(_ orderedIDs: [UUID]) {
        let old = homeOrder
        homeOrder = orderedIDs; repairOrders()
        do { try persist(snapshot) } catch { homeOrder = old; lastError = error.localizedDescription }
    }

    /// Persist the complete ranking order independently of content timestamps.
    func applyRankingReorder(_ orderedIDs: [UUID]) {
        let old = rankingOrder
        rankingOrder = orderedIDs; repairOrders()
        do { try persist(snapshot) } catch { rankingOrder = old; lastError = error.localizedDescription }
    }

    /// 删除条目，并移除对应的海报文件。
    func delete(_ item: MediaItem) {
        do { try remove(item) } catch { lastError = error.localizedDescription }
    }
    func remove(_ item: MediaItem) throws {
        let incoming = LibrarySnapshot(items: items.filter { $0.id != item.id },
                                       homeOrder: homeOrder.filter { $0 != item.id },
                                       rankingOrder: rankingOrder.filter { $0 != item.id })
        try applyImport(incoming)
    }

    // MARK: - 同步（导入 / 导出）

    /// 完整导入回滚点包含 JSON 和附件；同时保留旧版 JSON 备份名称。
    /// 导入前的回滚点：把当前库文件整份另存为 `Documents/导入前备份.json`（每次覆盖）。
    ///
    /// 用 `Data.write` 而不是 `FileManager.copyItem` —— 后者在目标已存在时会抛错，
    /// 而这里要的正是「覆盖上一次的备份」。
    ///
    /// 只备份元数据，不含海报。导入覆盖或删除的海报无法通过此文件恢复。
    func makeImportBackup() throws {
        guard !isPreview else { return }
        if loadFailed {
            let backup = directoryURL.appendingPathComponent("读取失败备份-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            for name in [LibraryFiles.libraryFileName, LibraryFiles.postersDirectoryName, LibraryFiles.artworkDirectoryName] {
                let original = directoryURL.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: original.path) {
                    try FileManager.default.copyItem(at: original, to: backup.appendingPathComponent(name))
                }
            }
            return
        }
        try LibraryArchive.commit(snapshot, to: directoryURL.appendingPathComponent("导入前完整备份"))
        try snapshot.encoded().write(to: directoryURL.appendingPathComponent(Self.importBackupFileName), options: .atomic)
    }

    /// Replace the complete local snapshot, including order and poster membership.
    func applyImport(_ incoming: LibrarySnapshot, replacingUnreadable: Bool = false) throws {
        try persist(incoming, replacingUnreadable: replacingUnreadable)
        loadFailed = false
        items = incoming.items
        homeOrder = incoming.homeOrder
        rankingOrder = incoming.rankingOrder
    }

    // MARK: - 海报文件

    func posterURL(for id: UUID) -> URL {
        postersDirectoryURL.appendingPathComponent("\(id.uuidString).jpg")
    }

    // MARK: - 编解码

    private static var decoder: JSONDecoder { LibraryCoding.decoder }
}

enum RepositoryError: LocalizedError {
    case duplicate
    var errorDescription: String? { String(localized: "收藏库已有相同作品，请打开已有条目。") }
}
