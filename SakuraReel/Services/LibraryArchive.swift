import Foundation

struct HomeOrderGroup: Codable, Hashable, Sendable {
    var month: YearMonth?
    var ids: [UUID]
}
struct RankingOrderGroup: Codable, Hashable, Sendable {
    var rating: Int
    var ids: [UUID]
}
struct LibraryDocument: Codable, Sendable {
    var schemaVersion = 1
    var libraryID = UUID()
    var revision: UInt64 = 0
    var entries: [LibraryEntry]
    private var draftPayloads: [UUID: MediaItem] = [:]
    var items: [MediaItem] {
        get { entries.map { draftPayloads[$0.id] ?? MediaItem(entry: $0) } }
        set {
            entries = newValue.map(\.entry)
            draftPayloads = Dictionary(newValue.filter { $0.poster != nil || $0.backdrop != nil || $0.logo != nil }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
    var homeGroups: [HomeOrderGroup]
    var rankingGroups: [RankingOrderGroup]
    /// Transfer context only. Never encoded, and never interpreted as a user-supplied path.
    var attachmentDirectory: URL?
    var warnings: [String] = []
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, libraryID, revision, homeGroups, rankingGroups
        case entries = "items"
    }
    init(items: [MediaItem] = []) {
        entries = []
        homeGroups = []
        rankingGroups = []
        self.items = items
        for item in items {
            let month = item.personal.watchedAt
            if let index = homeGroups.firstIndex(where: { $0.month == month }) { homeGroups[index].ids.append(item.id) }
            else { homeGroups.append(HomeOrderGroup(month: month, ids: [item.id])) }
        }
    }
    var homeOrder: [UUID] {
        homeGroups.sorted { ($0.month ?? YearMonth(year: 0, month: 0)) > ($1.month ?? YearMonth(year: 0, month: 0)) }.flatMap(\.ids)
    }
    var rankingOrder: [UUID] { rankedItems.map(\.id) }
    var homeItems: [MediaItem] { MediaSort.homeSorted(items, order: homeOrder) }
    var rankedItems: [MediaItem] { allRankedItems.filter { $0.status == .watched } }
    private var allRankedItems: [MediaItem] {
        let defaults = MediaSort.rankingDefaultSorted(items, homeOrder: homeOrder)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(items.map(\.rating)).sorted(by: >).flatMap { rating in
            if let manual = rankingGroups.first(where: { $0.rating == rating }) { return manual.ids.compactMap { byID[$0] } }
            return defaults.filter { $0.rating == rating }
        }
    }
    static func decode(_ data: Data) throws -> Self {
        struct Header: Decodable { var schemaVersion: Int }
        guard let header = try? LibraryCoding.decoder.decode(Header.self, from: data) else { throw LibraryArchiveError.invalid("旧格式或损坏的资料库，不支持读取。") }
        guard header.schemaVersion == 1 else { throw LibraryArchiveError.invalid("不支持资料库版本 \(header.schemaVersion)。") }
        let result = try LibraryCoding.decoder.decode(Self.self, from: data)
        try LibraryValidator.validate(result)
        return result
    }
    func encoded() throws -> Data {
        try LibraryValidator.validate(self)
        return try LibraryCoding.encoder.encode(self)
    }
    mutating func upsert(_ entry: MediaItem, now: Date = Date()) throws {
        var updated = entry
        let old = items.first { $0.id == entry.id }
        updated.createdAt = old?.createdAt ?? now
        updated.updatedAt = now
        if old?.personal.watchedAt != updated.personal.watchedAt || old == nil {
            for index in homeGroups.indices { homeGroups[index].ids.removeAll { $0 == entry.id } }
            homeGroups.removeAll { $0.ids.isEmpty }
            if let index = homeGroups.firstIndex(where: { $0.month == updated.personal.watchedAt }) {
                if old == nil { homeGroups[index].ids.insert(entry.id, at: 0) }
                else { homeGroups[index].ids.append(entry.id) }
            }
            else { homeGroups.append(HomeOrderGroup(month: updated.personal.watchedAt, ids: [entry.id])) }
        }
        if let index = items.firstIndex(where: { $0.id == updated.id }) { items[index] = updated }
        else { items.append(updated) }
        if old?.rating != updated.rating || old == nil {
            for index in rankingGroups.indices { rankingGroups[index].ids.removeAll { $0 == updated.id } }
            rankingGroups.removeAll { $0.ids.isEmpty }
            if let index = rankingGroups.firstIndex(where: { $0.rating == updated.rating }) {
                let defaults = MediaSort.rankingDefaultSorted(items, homeOrder: homeOrder).map(\.id)
                let positions = Dictionary(uniqueKeysWithValues: defaults.enumerated().map { ($0.element, $0.offset) })
                let insertion = rankingGroups[index].ids.firstIndex { positions[$0, default: 0] > positions[updated.id, default: 0] } ?? rankingGroups[index].ids.count
                rankingGroups[index].ids.insert(updated.id, at: insertion)
            }
        }
        try LibraryValidator.validate(self)
    }
    /// Merge only personal fields into the current entry; preserve artwork and work details.
    mutating func updatePersonalRecord(_ record: PersonalRecord, for id: UUID, now: Date = Date()) throws {
        guard var current = items.first(where: { $0.id == id }) else {
            throw LibraryArchiveError.invalid("作品已不存在。")
        }
        current.personal = record
        try upsert(current, now: now)
    }

    mutating func remove(_ id: UUID) throws {
        items.removeAll { $0.id == id }
        for index in homeGroups.indices { homeGroups[index].ids.removeAll { $0 == id } }
        for index in rankingGroups.indices { rankingGroups[index].ids.removeAll { $0 == id } }
        homeGroups.removeAll { $0.ids.isEmpty }; rankingGroups.removeAll { $0.ids.isEmpty }
        try LibraryValidator.validate(self)
    }
    /// Replace only the selected category's slots, preserving every other category's order.
    mutating func reorderHome(_ ids: [UUID], status: MediaStatus) throws {
        let current = homeItems.filter { $0.status == status }.map(\.id)
        guard ids.count == current.count, Set(ids) == Set(current) else {
            throw LibraryArchiveError.invalid("排序必须包含当前分类的全部条目且不能重复。")
        }
        var replacement = ids.makeIterator()
        let selected = Set(current)
        let merged = homeOrder.map { selected.contains($0) ? replacement.next()! : $0 }
        try reorder(merged, ranking: false)
    }

    mutating func reorder(_ ids: [UUID], ranking: Bool) throws {
        let visible = ranking ? rankingOrder : homeOrder
        guard ids.count == visible.count, Set(ids) == Set(visible) else { throw LibraryArchiveError.invalid("排序必须包含全部条目且不能重复。") }
        let current = ranking ? allRankedItems.map(\.id) : homeOrder
        var replacement = ids.makeIterator()
        let selected = Set(visible)
        let ids = current.map { selected.contains($0) ? replacement.next()! : $0 }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for (a, b) in zip(current, ids) {
            guard ranking ? byID[a]?.rating == byID[b]?.rating : byID[a]?.personal.watchedAt == byID[b]?.personal.watchedAt else {
                throw LibraryArchiveError.invalid(ranking ? "只能调整相同评分内的作品顺序。" : "只能调整相同观看年月内的作品顺序。")
            }
        }
        if ranking {
            for rating in Set(items.map(\.rating)) {
                let groupIDs = ids.filter { byID[$0]?.rating == rating }
                let oldIDs = current.filter { byID[$0]?.rating == rating }
                guard groupIDs != oldIDs else { continue }
                if let index = rankingGroups.firstIndex(where: { $0.rating == rating }) { rankingGroups[index].ids = groupIDs }
                else { rankingGroups.append(RankingOrderGroup(rating: rating, ids: groupIDs)) }
            }
        } else {
            for index in homeGroups.indices { homeGroups[index].ids = ids.filter { byID[$0]?.personal.watchedAt == homeGroups[index].month } }
        }
        try LibraryValidator.validate(self)
    }
}
typealias LibrarySnapshot = LibraryDocument

enum LibraryValidator {
    static func validate(_ document: LibraryDocument) throws {
        func require(_ valid: Bool, _ message: String) throws { if !valid { throw LibraryArchiveError.invalid(message) } }
        try require(document.schemaVersion == 1, "不支持的资料库版本。")
        try require(Set(document.items.map(\.id)).count == document.items.count, "条目 UUID 重复。")
        var sources = Set<TMDbIdentity>()
        for item in document.items {
            try require(!item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "片名不能为空。")
            try require((0...10).contains(item.rating), "评分必须是 0–10。")
            if let month = item.personal.watchedAt { try require((1...9999).contains(month.year) && (1...12).contains(month.month), "观看年月无效。") }
            try require(item.createdAt <= item.updatedAt, "条目修改时间早于创建时间。")
            for kind in AttachmentKind.allCases { try require(item.attachments[kind] == nil || item.attachments[kind] == kind.format, "附件格式无效。") }
            if let source = item.source {
                try require(source.remoteID > 0 && !source.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "TMDb 来源无效。")
                if case .season(_, let parent, let number) = source.tmdb { try require(parent > 0 && number >= 0, "季度来源不完整。") }
                try require(sources.insert(source.tmdb).inserted, "TMDb 作品身份重复。")
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: document.items.map { ($0.id, $0) })
        let homeIDs = document.homeGroups.flatMap(\.ids)
        try require(homeIDs.count == document.items.count && Set(homeIDs) == Set(byID.keys), "首页顺序存在重复、缺失或未知条目。")
        try require(Set(document.homeGroups.map(\.month)).count == document.homeGroups.count, "首页年月组重复。")
        for group in document.homeGroups {
            try require(!group.ids.isEmpty && group.ids.allSatisfy { byID[$0]?.personal.watchedAt == group.month }, "首页顺序包含跨年月条目。")
        }
        try require(Set(document.rankingGroups.map(\.rating)).count == document.rankingGroups.count, "排行榜评分组重复。")
        for group in document.rankingGroups {
            let expected = Set(document.items.filter { $0.rating == group.rating }.map(\.id))
            try require(!group.ids.isEmpty && Set(group.ids) == expected && group.ids.count == expected.count, "排行榜手动组存在重复、缺失、未知或跨评分条目。")
        }
    }
}

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

enum LibraryFiles {
    static let libraryFileName = "SakuraReelLibrary.json"
    static let postersDirectoryName = "Posters"
    static let artworkDirectoryName = "Artwork"
}

enum LibraryArchiveError: LocalizedError {
    case missingLibraryFile, unreadableLibraryFile
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .missingLibraryFile: return "这个文件夹里没有 SakuraReel 数据。"
        case .unreadableLibraryFile: return "数据文件已损坏或版本不兼容。"
        }
    }
}

struct ImportSummary {
    let cloudCount: Int
    let localCount: Int
    let deletedCount: Int
    var description: String {
        "云端 \(cloudCount) 部 · 本机 \(localCount) 部 · 将删除本机独有 \(deletedCount) 部。\n导入后本机将与云端完全一致。"
    }
}

private final class LibraryTransactionLocks: @unchecked Sendable {
    private let guardLock = NSLock()
    private var locks: [String: NSRecursiveLock] = [:]
    func lock(for folder: URL) -> NSRecursiveLock {
        guardLock.lock(); defer { guardLock.unlock() }
        let key = folder.resolvingSymlinksInPath().standardizedFileURL.path
        if let lock = locks[key] { return lock }
        let lock = NSRecursiveLock(); locks[key] = lock; return lock
    }
}

enum LibraryArchive {
    private static let transactionLocks = LibraryTransactionLocks()
    static func summary(incoming: LibrarySnapshot, local: LibrarySnapshot) -> ImportSummary {
        let cloudIDs = Set(incoming.items.map(\.id))
        return ImportSummary(cloudCount: incoming.items.count, localCount: local.items.count,
                             deletedCount: local.items.filter { !cloudIDs.contains($0.id) }.count)
    }

    static func read(from folder: URL, hydrate: Bool = true) throws -> LibrarySnapshot {
        return try withTransaction(in: folder) {
            try recoverPendingCommits(in: folder)
            let url = folder.appendingPathComponent(LibraryFiles.libraryFileName)
            guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryArchiveError.missingLibraryFile }
            var snapshot = try LibraryDocument.decode(readCoordinated(url))
            snapshot.attachmentDirectory = folder
            for index in snapshot.items.indices {
                let manifest = snapshot.items[index].attachments
                for kind in AttachmentKind.allCases where manifest[kind] != nil {
                    let file = folder.appendingPathComponent(kind.path(for: snapshot.items[index].id))
                    if !FileManager.default.fileExists(atPath: file.path) {
                        snapshot.warnings.append("\(snapshot.items[index].title)：缺少\(kind.rawValue)附件。")
                    } else if hydrate { snapshot.items[index][kind] = try readCoordinated(file) }
                }
                snapshot.items[index].attachments = manifest
            }
            return snapshot
        }
    }
    static func attachment(_ kind: AttachmentKind, id: UUID, from folder: URL) throws -> Data? {
        return try withTransaction(in: folder) {
            let url = folder.appendingPathComponent(kind.path(for: id))
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try readCoordinated(url)
        }
    }

    static func export(_ snapshot: LibrarySnapshot, to folder: URL) throws {
        try commit(snapshot, to: folder)
    }

    /// Only changed files are staged; unchanged images keep their original URLs and bytes.
    static func commit(_ snapshot: LibrarySnapshot, to folder: URL, replacingUnreadable: Bool = false) throws {
        try LibrarySyncDisk.commitLocal(snapshot, to: folder, replacingUnreadable: replacingUnreadable)
    }

    private static let coordinatorKey = "SakuraReel.transactionCoordinator"
    private static var activeCoordinator: NSFileCoordinator? {
        Thread.current.threadDictionary[coordinatorKey] as? NSFileCoordinator
    }
    static func withTransaction<T>(in folder: URL, _ body: () throws -> T) throws -> T {
        let lock = transactionLocks.lock(for: folder); lock.lock(); defer { lock.unlock() }
        if activeCoordinator != nil { return try body() }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?
        // Lock the small JSON, not its parent directory: do not materialize every cloud image.
        coordinator.coordinate(writingItemAt: folder.appendingPathComponent(LibraryFiles.libraryFileName), options: .forMerging, error: &coordinationError) { _ in
            Thread.current.threadDictionary[coordinatorKey] = coordinator
            defer { Thread.current.threadDictionary.removeObject(forKey: coordinatorKey) }
            result = Result { try body() }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    /// Recover an interrupted save before reading or writing the library. Backups stay until recovery succeeds.
    static func recoverPendingCommits(in folder: URL) throws {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        return try withTransaction(in: folder) {
            let manager = FileManager.default
            let children = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            let names = [LibraryFiles.postersDirectoryName, LibraryFiles.artworkDirectoryName, LibraryFiles.libraryFileName]
            for rollback in children where rollback.lastPathComponent.hasPrefix(".rollback-") && UUID(uuidString: String(rollback.lastPathComponent.dropFirst(10))) != nil {
                let manifest = rollback.appendingPathComponent("originals.json")
                if !manager.fileExists(atPath: rollback.appendingPathComponent("committed").path), manager.fileExists(atPath: manifest.path) {
                    let originals = try JSONDecoder().decode([String].self, from: Data(contentsOf: manifest))
                    guard Set(originals).isSubset(of: Set(names)) else { throw LibraryArchiveError.unreadableLibraryFile }
                    for name in names {
                        try coordinateMutation(at: folder.appendingPathComponent(name)) { destination in
                            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
                            if originals.contains(name) { try manager.copyItem(at: rollback.appendingPathComponent(name), to: destination) }
                        }
                    }
                }
                try manager.removeItem(at: rollback)
            }
            try LibraryFileTransaction.recover(in: folder)
            for staging in children where staging.lastPathComponent.hasPrefix(".staging-") && UUID(uuidString: String(staging.lastPathComponent.dropFirst(9))) != nil {
                try? manager.removeItem(at: staging)
            }
        }
    }

    static func coordinateMutation(at url: URL, body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var operationError: Error?
        (activeCoordinator ?? NSFileCoordinator()).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
            do { try body(coordinated) } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    static func readCoordinated(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var readError: Error?
        var result: Data?
        (activeCoordinator ?? NSFileCoordinator()).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do { result = try Data(contentsOf: readURL) } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return result
    }

    static func writeCoordinated(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        (activeCoordinator ?? NSFileCoordinator()).coordinate(writingItemAt: url, options: [], error: &coordinationError) { writeURL in
            do { try data.write(to: writeURL, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
