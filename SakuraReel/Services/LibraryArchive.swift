import Foundation

/// One snapshot owns both item data and the two independent, complete display orders.
struct LibrarySnapshot: Codable {
    var items: [MediaItem]
    var homeOrder: [UUID]
    var rankingOrder: [UUID]

    init(items: [MediaItem], homeOrder: [UUID], rankingOrder: [UUID]) {
        self.items = items
        self.homeOrder = Self.repaired(homeOrder, items: items, ranking: false)
        self.rankingOrder = Self.repaired(rankingOrder, items: items, ranking: true)
    }

    static func legacy(_ items: [MediaItem]) -> Self {
        Self(items: items,
             homeOrder: MediaSort.homeSorted(items, mode: .default).map(\.id),
             rankingOrder: MediaSort.rankingSorted(items).map(\.id))
    }

    static func decode(_ data: Data) throws -> Self {
        if let snapshot = try? LibraryCoding.decoder.decode(Self.self, from: data) {
            return Self(items: snapshot.items, homeOrder: snapshot.homeOrder, rankingOrder: snapshot.rankingOrder)
        }
        return .legacy(try LibraryCoding.decoder.decode([MediaItem].self, from: data))
    }

    func encoded() throws -> Data { try LibraryCoding.encoder.encode(self) }

    /// Keep valid IDs once, then place missing IDs using the old default comparator.
    private static func repaired(_ order: [UUID], items: [MediaItem], ranking: Bool) -> [UUID] {
        let ids = Set(items.map(\.id))
        var seen: Set<UUID> = []
        var result = order.filter { ids.contains($0) && seen.insert($0).inserted }
        let defaults = ranking ? MediaSort.rankingDefaultSorted(items) : MediaSort.homeSorted(items, mode: .default)
        for item in defaults where !seen.contains(item.id) {
            let key = ranking ? MediaSort.rankingGroupKey(of: item) : MediaSort.groupKey(of: item)
            let positions = Dictionary(uniqueKeysWithValues: items.map { ($0.id, ranking ? MediaSort.rankingGroupKey(of: $0) : MediaSort.groupKey(of: $0)) })
            let sameGroup = result.indices.filter { positions[result[$0]] == key }
            let defaultIDs = defaults.filter { (ranking ? MediaSort.rankingGroupKey(of: $0) : MediaSort.groupKey(of: $0)) == key }.map(\.id)
            let preferred = defaultIDs.prefix { $0 != item.id }
            let prior = preferred.last { seen.contains($0) }
            let insertion = prior.flatMap { result.firstIndex(of: $0).map { $0 + 1 } } ?? sameGroup.first ?? result.count
            result.insert(item.id, at: insertion)
            seen.insert(item.id)
        }
        return result
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
}

enum LibraryArchiveError: LocalizedError {
    case missingLibraryFile, unreadableLibraryFile
    var errorDescription: String? {
        switch self {
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

enum LibraryArchive {
    static func summary(incoming: LibrarySnapshot, local: LibrarySnapshot) -> ImportSummary {
        let cloudIDs = Set(incoming.items.map(\.id))
        return ImportSummary(cloudCount: incoming.items.count, localCount: local.items.count,
                             deletedCount: local.items.filter { !cloudIDs.contains($0.id) }.count)
    }

    static func export(_ snapshot: LibrarySnapshot, to folder: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let postersFolder = folder.appendingPathComponent(LibraryFiles.postersDirectoryName, isDirectory: true)
        try manager.createDirectory(at: postersFolder, withIntermediateDirectories: true)
        var expected: Set<String> = []
        for item in snapshot.items {
            guard let poster = item.poster else { continue }
            let name = "\(item.id.uuidString).jpg"
            expected.insert(name)
            try writeCoordinated(poster, to: postersFolder.appendingPathComponent(name))
        }
        let existing = (try? manager.contentsOfDirectory(atPath: postersFolder.path)) ?? []
        for name in existing where name.hasSuffix(".jpg") && UUID(uuidString: String(name.dropLast(4))) != nil && !expected.contains(name) {
            try manager.removeItem(at: postersFolder.appendingPathComponent(name))
        }
        try writeCoordinated(snapshot.encoded(), to: folder.appendingPathComponent(LibraryFiles.libraryFileName))
    }

    static func read(from folder: URL) throws -> LibrarySnapshot {
        let url = folder.appendingPathComponent(LibraryFiles.libraryFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryArchiveError.missingLibraryFile }
        guard let data = try? readCoordinated(url), var snapshot = try? LibrarySnapshot.decode(data) else {
            throw LibraryArchiveError.unreadableLibraryFile
        }
        let posters = folder.appendingPathComponent(LibraryFiles.postersDirectoryName, isDirectory: true)
        snapshot.items = snapshot.items.map { item in
            var copy = item
            let posterURL = posters.appendingPathComponent("\(item.id.uuidString).jpg")
            copy.poster = FileManager.default.fileExists(atPath: posterURL.path) ? try? readCoordinated(posterURL) : nil
            return copy
        }
        return snapshot
    }

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
