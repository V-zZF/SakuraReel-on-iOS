import Foundation

/// 库文件的编解码配置。
///
/// 本机库文件与导出的同步文件必须格式完全一致，所以两处共用这一份配置 ——
/// 否则「导出的文件能不能当备份手工放回 Documents」就成了未知数。
enum LibraryCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// 库文件的固定命名，本机 Documents 与同步文件夹共用同一套约定。
enum LibraryFiles {
    static let libraryFileName = "SakuraReelLibrary.json"
    static let postersDirectoryName = "Posters"
}

enum LibraryArchiveError: LocalizedError {
    /// 文件夹里没有 SakuraReelLibrary.json
    case missingLibraryFile
    /// 文件在，但解不开
    case unreadableLibraryFile

    var errorDescription: String? {
        switch self {
        case .missingLibraryFile: return "这个文件夹里没有 SakuraReel 数据。"
        case .unreadableLibraryFile: return "数据文件已损坏或版本不兼容。"
        }
    }
}

/// 一次导入的合并结果，用于写盘前的确认弹窗与写盘后的结果提示。
struct ImportSummary: Equatable {
    /// 本机没有、由文件带进来的条目
    var added = 0
    /// 两边都有、且文件里更新的条目
    var updated = 0
    /// 两边都有、但本机更新或相同的条目
    var skipped = 0
    /// 本机有、文件里没有的条目（不删，原样保留）
    var kept = 0
    /// 合并后因为组内序号撞车而被重编的条目数（0 = 没有发生冲突）
    var normalized = 0

    /// 这次导入实际会改动的条目数
    var changed: Int { added + updated }

    var description: String {
        var text = "新增 \(added) 条 · 更新 \(updated) 条 · 跳过 \(skipped) 条 · 保留本机独有 \(kept) 条"
        if normalized > 0 {
            text += "\n有 \(normalized) 条作品的组内顺序两边对不上，已按当前顺序重排。"
        }
        return text
    }
}

/// 导出 / 导入的纯逻辑。
///
/// 只依赖 Foundation —— 不 import SwiftUI、不 import Observation、不碰文档选择器、不碰
/// security-scoped bookmark。那几件事全在 `SyncFolder` 与 View 里。
///
/// 这条约束是刻意的：`MediaItem`、`MediaSort` 本来也只依赖 Foundation，所以这个文件能
/// 脱离 Xcode 直接编译跑断言（`Scripts/run-model-tests.sh`）。合并与索引修正是整套同步里
/// 最容易出错的部分，需要这个可测性。
///
/// 远端目录是 iCloud 云盘托管时，**读写都要过 `NSFileCoordinator`**：云盘上的文件可能被
/// 系统驱逐成「未下载」占位，协调读会等系统把它下载回来再放行。这件事会阻塞，所以
/// `export` / `read` 必须从后台线程调用，不要在主线​程直接跑。
enum LibraryArchive {

    // MARK: - 导出

    /// 把整库写到目标文件夹：`SakuraReelLibrary.json` + `Posters/<id>.jpg`，与本机结构一致。
    ///
    /// 全量覆盖。目标 `Posters/` 里**由本 App 命名**、但已不属于本库的图片会被删掉，
    /// 让那个文件夹就是本库的一份完整快照；命名不像本 App 产物的文件一律不碰 ——
    /// 用户可能把同步文件夹选在了自己已有的目录上，误删别人的图片是不可接受的。
    static func export(_ items: [MediaItem], to folder: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)

        let postersFolder = folder.appendingPathComponent(LibraryFiles.postersDirectoryName, isDirectory: true)
        try manager.createDirectory(at: postersFolder, withIntermediateDirectories: true)

        // 先写海报，JSON 最后写 —— JSON 是「这份快照是完整的」那个标志
        var expected: Set<String> = []
        for item in items {
            guard let poster = item.poster else { continue }
            let name = posterFileName(for: item.id)
            expected.insert(name)
            try writeCoordinated(poster, to: postersFolder.appendingPathComponent(name))
        }

        let existing = (try? manager.contentsOfDirectory(atPath: postersFolder.path)) ?? []
        for name in existing where isOurPosterFile(name) && !expected.contains(name) {
            try? manager.removeItem(at: postersFolder.appendingPathComponent(name))
        }

        let data = try LibraryCoding.encoder.encode(items)
        try writeCoordinated(data, to: folder.appendingPathComponent(LibraryFiles.libraryFileName))
    }

    // MARK: - 读取

    /// 从文件夹读回整库，海报一并读进内存（与 `MediaRepository.load()` 同一套约定）。
    ///
    /// 会被未下载的云盘文件阻塞，**必须从后台线程调用**。
    static func read(from folder: URL) throws -> [MediaItem] {
        let libraryURL = folder.appendingPathComponent(LibraryFiles.libraryFileName)
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            throw LibraryArchiveError.missingLibraryFile
        }
        guard let data = try? readCoordinated(libraryURL),
              let decoded = try? LibraryCoding.decoder.decode([MediaItem].self, from: data) else {
            throw LibraryArchiveError.unreadableLibraryFile
        }

        let postersFolder = folder.appendingPathComponent(LibraryFiles.postersDirectoryName, isDirectory: true)
        return decoded.map { item in
            var copy = item
            let posterURL = postersFolder.appendingPathComponent(posterFileName(for: item.id))
            copy.poster = FileManager.default.fileExists(atPath: posterURL.path)
                ? try? readCoordinated(posterURL)
                : nil
            return copy
        }
    }

    // MARK: - 合并

    /// 按 `id` 合并传入的库与本机库：**只做新增与更新，不删本机独有的条目**。
    ///
    /// 同一个 `id` 两边都有时，`updatedAt` 新的赢 —— 所以拿一份旧快照来导入，不会把本机
    /// 较新的数据倒退回去。
    static func merge(
        incoming: [MediaItem],
        into local: [MediaItem]
    ) -> (items: [MediaItem], summary: ImportSummary) {
        var merged = local
        var indexByID = indexMap(for: local)
        var summary = ImportSummary()

        for item in incoming {
            guard let index = indexByID[item.id] else {
                merged.append(item)
                indexByID[item.id] = merged.count - 1
                summary.added += 1
                continue
            }
            if wins(incoming: item, over: merged[index]) {
                merged[index] = item
                summary.updated += 1
            } else {
                summary.skipped += 1
            }
        }

        // 本机有、文件里没有的条目：一条都没动
        summary.kept = local.count - summary.updated - summary.skipped
        let normalized = normalizeIndices(merged)
        summary.normalized = normalized.fixedCount
        return (normalized.items, summary)
    }

    /// 同一个 `id` 的两份拷贝谁赢。
    ///
    /// `updatedAt` 完全相同时必须有一个**对称**的裁决。若写成「平局保本机」，两台设备合并
    /// 同一对库时会各自保留自己那份 —— A 导给 B、B 再导给 A 就会来回翻，永远合不拢。
    private static func wins(incoming: MediaItem, over local: MediaItem) -> Bool {
        if incoming.updatedAt != local.updatedAt { return incoming.updatedAt > local.updatedAt }
        if incoming.sortIndex != local.sortIndex { return incoming.sortIndex < local.sortIndex }
        return (incoming.rankIndex ?? 0) < (local.rankIndex ?? 0)
    }

    // MARK: - 索引修正

    /// 修正合并后可能撞车的手动序号，返回修好的数组与被重编的条目数。
    ///
    /// `sortIndex`（同观看年月组）与 `rankIndex`（同评分组）都是**每组各自 0…n-1**。两台设备
    /// 各自排过序之后再合并，同一组里就会冒出重复值 —— 而 `MediaSort` 的比较器最后一级正是
    /// 这个序号，Swift 的 `sorted` 又不保证稳定，结果是这两条的先后每次刷新都可能不同。
    ///
    /// 只重编**已经不合法**的组，没问题的组一条都不动，因此不会抹平任何一台设备排好的顺序。
    /// 这是数据修正，不涉及排序规则本身，也不改 `updatedAt` —— 索引是派生数据，动了它会让
    /// 一次纯归一化伪装成内容更新，反而吃掉对方更晚的内容编辑。
    static func normalizeIndices(_ items: [MediaItem]) -> (items: [MediaItem], fixedCount: Int) {
        var result = items
        var fixedCount = 0

        // 首页：同观看年月组。合法 = 组内 sortIndex 互不相同。
        // 组内所有条目同年同月，`MediaSort.homeSorted` 的比较器在这里只剩 `sortIndex` 一级。
        let homeGroups = Dictionary(grouping: result, by: { MediaSort.groupKey(of: $0) })
        for group in homeGroups.values where hasDuplicate(group.map(\.sortIndex)) {
            let ordered = orderedForReindex(group) { $0.sortIndex < $1.sortIndex }
            assign(&result, ordered) { $0.sortIndex = $1 }
            fixedCount += ordered.count
        }

        // 排行榜：同评分组。合法 = 全都没手动排过（全 nil），或者全排过且互不相同。
        // 「一半 nil 一半有值」也算冲突：`MediaSort` 里 nil 按 0 参与比较，会和真正的 0 号
        // 静默并列，退到观看时间再比 —— 而观看时间也相同时顺序就是未定义的。
        let ratingGroups = Dictionary(grouping: result, by: { MediaSort.rankingGroupKey(of: $0) })
        for group in ratingGroups.values where isRankIndexConflict(group.map(\.rankIndex)) {
            let ordered = orderedForReindex(group, by: MediaSort.rankingAreInIncreasingOrder)
            assign(&result, ordered) { $0.rankIndex = $1 }
            fixedCount += ordered.count
        }

        return (result, fixedCount)
    }

    // MARK: - 内部工具

    private static func posterFileName(for id: UUID) -> String {
        "\(id.uuidString).jpg"
    }

    /// 文件名是不是本 App 生成的海报（`<UUID>.jpg`）。
    /// 清理目标目录时只认这个形状，避免误删用户放在同一目录里的其它图片。
    private static func isOurPosterFile(_ name: String) -> Bool {
        guard name.hasSuffix(".jpg") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }

    private static func indexMap(for items: [MediaItem]) -> [UUID: Int] {
        Dictionary(items.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }

    private static func hasDuplicate(_ values: [Int]) -> Bool {
        values.count != Set(values).count
    }

    private static func isRankIndexConflict(_ values: [Int?]) -> Bool {
        if values.allSatisfy({ $0 == nil }) { return false }          // 这组从没手动排过
        let numbers = values.map { $0 ?? 0 }
        if values.allSatisfy({ $0 != nil }), Set(numbers).count == numbers.count { return false }
        return true
    }

    /// 决定重编后的顺序：先按给定的比较器，比较器分不出先后的用 `createdAt` / `id` 兜底。
    ///
    /// 兜底**不能**用数组下标 —— 两台设备的数组顺序本来就不同，那样会让同一份库在两边
    /// 归一化出不同的顺序。`createdAt` 与 `id` 是两端一致的数据，才能保证收敛。
    private static func orderedForReindex(
        _ group: [MediaItem],
        by isOrderedBefore: (MediaItem, MediaItem) -> Bool
    ) -> [MediaItem] {
        group.sorted { lhs, rhs in
            if isOrderedBefore(lhs, rhs) { return true }
            if isOrderedBefore(rhs, lhs) { return false }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// 把 `ordered` 的顺序压成连续序号，写回 `result` 中对应的条目。
    private static func assign(
        _ result: inout [MediaItem],
        _ ordered: [MediaItem],
        _ set: (inout MediaItem, Int) -> Void
    ) {
        for (offset, item) in ordered.enumerated() {
            guard let target = result.firstIndex(where: { $0.id == item.id }) else { continue }
            set(&result[target], offset)
        }
    }

    // MARK: - 协调读写

    /// 协调读：目标文件若在云盘上还没下载，这里会等系统下载完成再返回。
    private static func readCoordinated(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var readError: Error?
        var result: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do { result = try Data(contentsOf: readURL) } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return result
    }

    /// 协调写。
    ///
    /// 选项用 `[]` 而不是 `.forReplacing` —— 后者按 Apple 的定义是「用另一个文件整体替换」，
    /// 而这里只是更新文件内容（`.atomic` 内部走临时文件 + rename，那是实现细节，不算替换语义）。
    /// `.atomic` 必须留在协调块内，否则云盘的后台进程会看到那个匿名临时文件。
    private static func writeCoordinated(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { writeURL in
            do { try data.write(to: writeURL, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
