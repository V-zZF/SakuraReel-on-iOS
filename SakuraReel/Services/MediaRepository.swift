import Foundation
import Observation

/// All disk work runs on this actor; its synchronous operations cannot interleave.
actor LibraryStorage {
    let directory: URL
    private var cache: [String: Data] = [:]
    private var cacheBytes = 0
    init(directory: URL) { self.directory = directory }
    func load() throws -> LibraryDocument {
        cache.removeAll(); cacheBytes = 0
        try LibraryArchive.recoverPendingCommits(in: directory)
        let file = directory.appendingPathComponent(LibraryFiles.libraryFileName)
        if !FileManager.default.fileExists(atPath: file.path) {
            let empty = LibraryDocument()
            try LibraryArchive.commit(empty, to: directory)
        }
        return try LibraryArchive.read(from: directory, hydrate: false)
    }
    func commit(_ document: LibraryDocument, expected: LibraryDocument? = nil) throws {
        if let expected {
            let disk = try LibraryArchive.read(from: directory, hydrate: false)
            guard disk.libraryID == expected.libraryID && disk.revision == expected.revision else {
                throw LibraryArchiveError.invalid("资料库文件已被修改，请重新读取后再保存。")
            }
        }
        try LibraryArchive.commit(document, to: directory)
        cache.removeAll(); cacheBytes = 0
    }
    func readAttachment(_ kind: AttachmentKind, id: UUID, revision: UInt64) throws -> Data? {
        let key = "\(revision):\(id):\(kind.rawValue)"
        if let data = cache[key] { return data }
        guard let data = try LibraryArchive.attachment(kind, id: id, from: directory) else { return nil }
        if cacheBytes + data.count > 32 * 1024 * 1024 { cache.removeAll(); cacheBytes = 0 }
        if data.count <= 32 * 1024 * 1024 { cache[key] = data; cacheBytes += data.count }
        return data
    }
    func hydrated(_ document: LibraryDocument) throws -> LibraryDocument {
        var copy = document
        for index in copy.items.indices {
            let manifest = copy.items[index].attachments
            for kind in AttachmentKind.allCases where manifest[kind] != nil {
                copy.items[index][kind] = try readAttachment(kind, id: copy.items[index].id, revision: document.revision)
            }
            copy.items[index].attachments = manifest
        }
        copy.attachmentDirectory = nil
        return copy
    }
    func backup(_ document: LibraryDocument, unreadable: Bool) throws {
        if unreadable {
            let folder = directory.appendingPathComponent("读取失败备份-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in [LibraryFiles.libraryFileName, LibraryFiles.postersDirectoryName, LibraryFiles.artworkDirectoryName] {
                let source = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name)) }
            }
        } else {
            try LibraryArchive.commit(hydrated(document), to: directory.appendingPathComponent("导入前完整备份"))
        }
    }
}

@MainActor @Observable
final class MediaRepository {
    static let libraryFileName = LibraryFiles.libraryFileName
    static let postersDirectoryName = LibraryFiles.postersDirectoryName
    var lastError: String?
    private(set) var isLoading = true
    private(set) var document = LibraryDocument()
    private var byID: [UUID: MediaItem] = [:]
    private var bySource: [TMDbIdentity: UUID] = [:]
    private let storage: LibraryStorage
    private let directory: URL
    private let isPreview: Bool
    private var previewPayloads: [UUID: MediaItem] = [:]
    private var loadFailed = false
    private var initialization: Task<Void, Never>?
    private var writing = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    var items: [MediaItem] { document.items }
    var homeOrder: [UUID] { document.homeOrder }
    var rankingOrder: [UUID] { document.rankingOrder }
    var homeItems: [MediaItem] { document.homeItems }
    var rankingItems: [MediaItem] { document.rankedItems }
    var snapshot: LibrarySnapshot { document }

    init(seedItems: [MediaItem]? = nil, directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storage = LibraryStorage(directory: self.directory)
        isPreview = seedItems != nil
        if let seedItems {
            previewPayloads = Dictionary(seedItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            publish(LibraryDocument(items: seedItems)); isLoading = false
        }
        else { initialization = Task { await load() } }
    }
    func waitUntilLoaded() async { await initialization?.value }
    private func acquire() async {
        if writing { await withCheckedContinuation { waiting.append($0) } }
        else { writing = true }
    }
    private func release() {
        if waiting.isEmpty { writing = false }
        else { waiting.removeFirst().resume() }
    }
    private func publish(_ value: LibraryDocument) {
        document = value
        document.items = value.items.map(\.lightweight)
        document.attachmentDirectory = directory
        byID = Dictionary(value.items.map { ($0.id, $0.lightweight) }, uniquingKeysWith: { first, _ in first })
        bySource = Dictionary(value.items.compactMap { item in item.source.map { ($0.tmdb, item.id) } }, uniquingKeysWith: { first, _ in first })
    }
    func load() async {
        await acquire(); defer { release(); isLoading = false }
        do {
            let loaded = try await storage.load()
            publish(loaded); loadFailed = false
            lastError = loaded.warnings.isEmpty ? nil : loaded.warnings.joined(separator: "\n")
        } catch { loadFailed = true; lastError = error.localizedDescription }
    }
    func duplicate(for source: MediaSource, excluding id: UUID? = nil) -> MediaItem? {
        guard let found = bySource[source.tmdb], found != id else { return nil }
        return byID[found]
    }
    func attachment(_ kind: AttachmentKind, for id: UUID) async -> Data? {
        await waitUntilLoaded()
        guard byID[id]?.attachments[kind] != nil else { return nil }
        if isPreview { return previewPayloads[id]?[kind] }
        do { return try await storage.readAttachment(kind, id: id, revision: document.revision) }
        catch { lastError = error.localizedDescription; return nil }
    }
    func editingItem(for id: UUID) async throws -> MediaItem {
        await waitUntilLoaded(); await acquire(); defer { release() }
        guard var item = byID[id] else { throw RepositoryError.notFound }
        if isPreview { return previewPayloads[id] ?? item }
        let manifest = item.attachments
        for kind in AttachmentKind.allCases where manifest[kind] != nil {
            item[kind] = try await storage.readAttachment(kind, id: id, revision: document.revision)
        }
        item.attachments = manifest
        return item
    }
    private func commit(_ candidate: LibraryDocument) async throws {
        guard !loadFailed else { throw LibraryArchiveError.unreadableLibraryFile }
        var next = candidate
        guard document.revision < UInt64.max else { throw LibraryArchiveError.invalid("资料库版本计数已达上限。") }
        next.revision = document.revision + 1
        next.attachmentDirectory = directory
        try LibraryValidator.validate(next)
        if !isPreview { try await storage.commit(next, expected: document) }
        if isPreview { previewPayloads = Dictionary(next.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
        publish(next); lastError = nil
    }
    func upsert(_ item: MediaItem) async throws {
        await waitUntilLoaded(); await acquire(); defer { release() }
        if let source = item.source, duplicate(for: source, excluding: item.id) != nil { throw RepositoryError.duplicate }
        var next = document
        try next.upsert(item)
        try await commit(next)
    }
    func updatePersonalRecord(_ record: PersonalRecord, for id: UUID) async throws {
        await waitUntilLoaded(); await acquire(); defer { release() }
        guard byID[id] != nil else { throw RepositoryError.notFound }
        var next = document
        try next.updatePersonalRecord(record, for: id)
        try await commit(next)
    }

    func applyMetadata(_ draft: TMDbImportDraft, fields: Set<MetadataField>, to id: UUID) async throws {
        await waitUntilLoaded(); await acquire(); defer { release() }
        guard let item = byID[id] else { throw RepositoryError.notFound }
        if duplicate(for: draft.source, excluding: id) != nil { throw RepositoryError.duplicate }
        var next = document
        try next.upsert(draft.merging(into: item, fields: fields))
        try await commit(next)
    }
    func applyHomeReorder(_ ids: [UUID]) async throws {
        try await reorder(ids, ranking: false)
    }
    func applyRankingReorder(_ ids: [UUID]) async throws {
        try await reorder(ids, ranking: true)
    }
    private func reorder(_ ids: [UUID], ranking: Bool) async throws {
        await waitUntilLoaded(); await acquire(); defer { release() }
        var next = document
        try next.reorder(ids, ranking: ranking)
        try await commit(next)
    }
    func delete(_ item: MediaItem) async {
        do { try await remove(item) } catch { lastError = error.localizedDescription }
    }
    func remove(_ item: MediaItem) async throws {
        await waitUntilLoaded(); await acquire(); defer { release() }
        var next = document; try next.remove(item.id); try await commit(next)
    }
    func exportSnapshot() async throws -> LibrarySnapshot {
        await waitUntilLoaded(); await acquire(); defer { release() }
        guard !loadFailed else { throw LibraryArchiveError.unreadableLibraryFile }
        return try await storage.hydrated(document)
    }
    func makeImportBackup() async throws {
        await waitUntilLoaded(); await acquire(); defer { release() }
        if !isPreview { try await storage.backup(document, unreadable: loadFailed) }
    }
    func applyImport(_ incoming: LibrarySnapshot, replacingUnreadable: Bool = false, backup: Bool = false) async throws {
        await waitUntilLoaded(); await acquire(); defer { release() }
        guard !loadFailed || replacingUnreadable else { throw LibraryArchiveError.unreadableLibraryFile }
        try LibraryValidator.validate(incoming)
        if backup && !isPreview { try await storage.backup(document, unreadable: loadFailed) }
        var next = incoming
        guard max(document.revision, incoming.revision) < UInt64.max else { throw LibraryArchiveError.invalid("资料库版本计数已达上限。") }
        next.revision = max(document.revision, incoming.revision) + 1
        if !isPreview { try await storage.commit(next) }
        loadFailed = false; publish(next)
        lastError = incoming.warnings.isEmpty ? nil : incoming.warnings.joined(separator: "\n")
    }
}

enum RepositoryError: LocalizedError {
    case duplicate, notFound
    var errorDescription: String? {
        switch self {
        case .duplicate: String(localized: "收藏库已有相同作品，请打开已有条目。")
        case .notFound: String(localized: "作品已不存在。")
        }
    }
}
