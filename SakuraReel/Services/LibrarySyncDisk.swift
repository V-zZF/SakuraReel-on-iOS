import Foundation

/// Recoverable per-file installation. The journal exists before any visible mutation.
enum LibraryFileTransaction {
    struct Journal: Codable { var paths: [String]; var originals: [String] }
    static let ownerID: String = {
        let defaults = UserDefaults.standard, key = "SakuraReel.syncTransactionOwner"
        if let saved = defaults.string(forKey: key) { return saved }
        let id = UUID().uuidString; defaults.set(id, forKey: key); return id
    }()
    static func managed(_ path: String) -> Bool {
        if [LibraryFiles.libraryFileName, LibrarySyncState.fileName].contains(path) { return true }
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if pieces.count == 2, pieces[0] == "Posters", pieces[1].hasSuffix(".jpg") { return UUID(uuidString: String(pieces[1].dropLast(4))) != nil }
        return pieces.count == 3 && pieces[0] == "Artwork" && UUID(uuidString: pieces[1]) != nil && ["backdrop.jpg", "logo.png"].contains(pieces[2])
    }
    struct IO { var readBytes = 0; var writtenBytes = 0 }
    @discardableResult
    static func commit(writes: [String: Data], deleting: Set<String>, to folder: URL, expected: SyncVersion? = nil, failAfterInstall: Int? = nil) throws -> IO {
        try LibraryArchive.withTransaction(in: folder) {
            let manager = FileManager.default
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try LibraryArchive.recoverPendingCommits(in: folder)
            if let expected, try LibrarySyncDisk.version(in: folder) != expected { throw LibrarySyncError.changed }
            let paths = Set(writes.keys).union(deleting).sorted {
                func priority(_ path: String) -> Int { path == LibrarySyncState.fileName ? 2 : (path == LibraryFiles.libraryFileName ? 1 : 0) }
                return priority($0) == priority($1) ? $0 < $1 : priority($0) < priority($1)
            }
            guard paths.allSatisfy(managed), Set(writes.keys).isDisjoint(with: deleting) else { throw LibraryArchiveError.invalid("同步事务包含无效路径。") }
            guard !paths.isEmpty else { return IO() }
            var io = IO()
            let journalFolder = folder.appendingPathComponent(".sync-transaction-" + UUID().uuidString)
            try manager.createDirectory(at: journalFolder, withIntermediateDirectories: true)
            // Failure during preparation cannot have touched visible data.
            var journalWritten = false
            do {
                // File providers may deliver another device's journal before its commit
                // marker. Only its owner may roll it back; foreign journals are inert.
                try LibraryArchive.writeCoordinated(Data(ownerID.utf8), to: journalFolder.appendingPathComponent("owner"))
                var originals: [String] = []
                for path in paths {
                    let destination = folder.appendingPathComponent(path)
                    if manager.fileExists(atPath: destination.path) {
                        let backup = journalFolder.appendingPathComponent("old/" + path)
                        try manager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let original = try LibraryArchive.readCoordinated(destination)
                        try LibraryArchive.writeCoordinated(original, to: backup)
                        if path != LibraryFiles.libraryFileName && path != LibrarySyncState.fileName {
                            io.readBytes += original.count; io.writtenBytes += original.count
                        }
                        originals.append(path)
                    }
                    if let bytes = writes[path] {
                        let stage = journalFolder.appendingPathComponent("new/" + path)
                        try manager.createDirectory(at: stage.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try LibraryArchive.writeCoordinated(bytes, to: stage)
                        if path != LibraryFiles.libraryFileName && path != LibrarySyncState.fileName { io.writtenBytes += bytes.count }
                    }
                }
                try SyncCoding.encode(Journal(paths: paths, originals: originals)).write(to: journalFolder.appendingPathComponent("journal.json"), options: .atomic)
                journalWritten = true
                for (index, path) in paths.enumerated() {
                    let destination = folder.appendingPathComponent(path)
                    try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try LibraryArchive.coordinateMutation(at: destination) { url in
                        if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
                        if writes[path] != nil { try manager.moveItem(at: journalFolder.appendingPathComponent("new/" + path), to: url) }
                    }
                    if failAfterInstall == index + 1 { throw LibrarySyncError.injectedFailure }
                }
                try Data().write(to: journalFolder.appendingPathComponent("committed"), options: .atomic)
            } catch {
                if journalWritten { try recover(in: folder) }
                else { try? manager.removeItem(at: journalFolder) }
                throw error
            }
            try? manager.removeItem(at: journalFolder)
            return io
        }
    }
    static func recover(in folder: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.path) else { return }
        for journalFolder in try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let name = journalFolder.lastPathComponent
            guard name.hasPrefix(".sync-transaction-"), UUID(uuidString: String(name.dropFirst(18))) != nil else { continue }
            let owner = journalFolder.appendingPathComponent("owner")
            guard manager.fileExists(atPath: owner.path), String(data: try LibraryArchive.readCoordinated(owner), encoding: .utf8) == ownerID else { continue }
            let journalURL = journalFolder.appendingPathComponent("journal.json")
            if manager.fileExists(atPath: journalURL.path), !manager.fileExists(atPath: journalFolder.appendingPathComponent("committed").path) {
                let journal = try SyncCoding.decode(Journal.self, LibraryArchive.readCoordinated(journalURL))
                guard journal.paths.allSatisfy(managed), Set(journal.paths).count == journal.paths.count,
                      Set(journal.originals).isSubset(of: Set(journal.paths)) else { throw LibraryArchiveError.invalid("同步回滚记录无效。") }
                // Read every backup before restoring anything. Never discard an incomplete backup.
                var originals: [String: Data] = [:]
                for path in journal.originals { originals[path] = try LibraryArchive.readCoordinated(journalFolder.appendingPathComponent("old/" + path)) }
                for path in journal.paths {
                    let destination = folder.appendingPathComponent(path)
                    if let bytes = originals[path] {
                        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try LibraryArchive.writeCoordinated(bytes, to: destination)
                    } else {
                        try LibraryArchive.coordinateMutation(at: destination) { url in
                            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
                        }
                    }
                }
            }
            try manager.removeItem(at: journalFolder)
        }
    }
}

enum LibrarySyncError: LocalizedError {
    case changed, injectedFailure
    var errorDescription: String? {
        switch self {
        case .changed: "同步期间资料库已发生变化，请重新同步。"
        case .injectedFailure: "测试注入的提交失败。"
        }
    }
}

struct SyncFileChanges: Sendable {
    var writes: [String: Data] = [:]
    var deleting = Set<String>()
    var attachments = 0
    var skipped = 0
    var bytes = 0
}

enum LibrarySyncDisk {
    static func version(in folder: URL) throws -> SyncVersion {
        try LibraryArchive.withTransaction(in: folder) {
        func hash(_ name: String) throws -> String? {
            let url = folder.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? SyncCoding.hash(try LibraryArchive.readCoordinated(url)) : nil
        }
        return try SyncVersion(library: hash(LibraryFiles.libraryFileName), manifest: hash(LibrarySyncState.fileName))
        }
    }
    static func read(from folder: URL, empty: LibraryDocument? = nil, strict: Bool = true, recovering baseline: LibrarySyncState? = nil) throws -> SyncEndpoint {
        try LibraryArchive.withTransaction(in: folder) {
            try LibraryArchive.recoverPendingCommits(in: folder)
            let version = try version(in: folder)
            let document: LibraryDocument
            if version.library == nil {
                guard let empty, version.manifest == nil, baseline == nil else { throw LibraryArchiveError.missingLibraryFile }
                document = empty
            } else { document = try LibraryArchive.read(from: folder, hydrate: false) }
            var saved: LibrarySyncState?
            var recoveredManifest = false
            if version.manifest != nil {
                let data = try LibraryArchive.readCoordinated(folder.appendingPathComponent(LibrarySyncState.fileName))
                struct Header: Decodable { var version: Int }
                if let header = try? SyncCoding.decode(Header.self, data), header.version != 1 { throw LibraryArchiveError.invalid("不支持这个同步清单版本。") }
                do { saved = try SyncCoding.decode(LibrarySyncState.self, data) }
                catch {
                    guard let baseline else { throw LibraryArchiveError.invalid("同步清单损坏且没有可信同步基线，未覆盖任何文件。请从完整备份恢复后重试。") }
                    try validate(baseline); saved = baseline; recoveredManifest = true
                }
                do { try validate(saved!) }
                catch {
                    guard let baseline else { throw error }
                    try validate(baseline); saved = baseline; recoveredManifest = true
                }
            } else if let baseline {
                try validate(baseline); saved = baseline; recoveredManifest = true
            }
            let canonical = SyncCoding.hash(try document.encoded())
            if let saved, saved.libraryHash == canonical, !recoveredManifest {
                guard Set(saved.records.keys) == Set(document.entries.map { $0.id.uuidString }), document.entries.allSatisfy({ saved.records[$0.id.uuidString]?.entry == $0 }) else {
                    throw LibraryArchiveError.invalid("同步清单与作品资料不一致。")
                }
                for record in saved.records.values {
                    for kind in AttachmentKind.allCases where record.entry.attachments[kind] != nil {
                        if strict && (record.files[kind.rawValue] == nil || (try? folder.appendingPathComponent(kind.path(for: record.entry.id)).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != true) {
                            throw LibraryArchiveError.invalid("\(record.entry.title)：缺少\(kind.rawValue)附件，未同步。")
                        }
                    }
                }
                return SyncEndpoint(document: document, state: saved, folder: folder, version: version)
            }
            if let saved, !recoveredManifest, saved.libraryHash != canonical, strict {
                for entry in document.entries {
                    for kind in AttachmentKind.allCases where entry.attachments[kind] != nil {
                        let bytes = try LibraryArchive.readCoordinated(folder.appendingPathComponent(kind.path(for: entry.id)))
                        if let expected = saved.records[entry.id.uuidString]?.files[kind.rawValue], SyncFingerprint(bytes) != expected {
                            throw LibraryArchiveError.invalid("同步文件尚未形成一致快照，未提交。请等待文件提供商完成更新后重试。")
                        }
                    }
                }
                throw LibraryArchiveError.invalid("资料库与同步清单不一致，未提交。请等待文件提供商完成更新后重试；恢复备份时须同时恢复 JSON 与清单。")
            }
            // A legacy archive or a corrupt/missing manifest with a trusted baseline.
            var bytes = 0
            let rebuilt = try track(document, old: saved, folder: folder, strict: strict, forceRead: true, bytesRead: &bytes)
            return SyncEndpoint(document: document, state: rebuilt.state, folder: folder, version: version, indexedBytes: bytes)
        }
    }
    static func validate(_ state: LibrarySyncState) throws {
        func validStamp(_ stamp: SyncStamp) throws {
            guard stamp.date.timeIntervalSince1970.isFinite, !stamp.operation.isEmpty else { throw LibraryArchiveError.invalid("同步时间记录无效。") }
        }
        guard state.libraryHash.count == 64, state.libraryHash.allSatisfy({ $0.isHexDigit }) else { throw LibraryArchiveError.invalid("同步资料库摘要无效。") }
        guard state.version == 1 else { throw LibraryArchiveError.invalid("不支持这个同步清单版本。") }
        try LibraryValidator.validate(LibraryDocument(items: state.records.values.map { MediaItem(entry: $0.entry) }))
        for (id, record) in state.records {
            guard UUID(uuidString: id)?.uuidString == id, record.entry.id.uuidString == id,
                  Set(record.fields.keys) == Set(SyncFields.names), record.fields.values.allSatisfy({ $0.date.timeIntervalSince1970.isFinite && !$0.operation.isEmpty }),
                  record.files.keys.allSatisfy({ AttachmentKind(rawValue: $0) != nil }) else { throw LibraryArchiveError.invalid("同步字段记录无效。") }
            if let restored = record.restoredAfter { try validStamp(restored) }
            for (kind, file) in record.files {
                guard file.size >= 0, file.sha256.count == 64, file.sha256.allSatisfy({ $0.isHexDigit }), record.entry.attachments[AttachmentKind(rawValue: kind)!] != nil else {
                    throw LibraryArchiveError.invalid("同步图片摘要无效。")
                }
            }
        }
        for (old, new) in state.aliases where UUID(uuidString: old)?.uuidString != old || UUID(uuidString: new)?.uuidString != new || old == new {
            throw LibraryArchiveError.invalid("同步 UUID 别名无效。")
        }
        for key in state.aliases.keys {
            var seen = Set<String>(), next = key
            while let value = state.aliases[next] {
                guard seen.insert(next).inserted else { throw LibraryArchiveError.invalid("同步 UUID 别名存在循环。") }; next = value
            }
        }
        for (id, deletion) in state.deletions {
            try validStamp(deletion.stamp)
            for stamp in deletion.basis.values { try validStamp(stamp) }
            guard UUID(uuidString: id)?.uuidString == id, Set(deletion.basis.keys) == Set(SyncFields.names) else { throw LibraryArchiveError.invalid("同步删除记录无效。") }
        }
        let known = Set(state.records.keys).union(state.deletions.keys).union(state.aliases.keys).union(state.aliases.values)
        for order in Array(state.home.values) + Array(state.ranking.values) {
            try validStamp(order.stamp)
            guard Set(order.ids).count == order.ids.count, order.ids.allSatisfy({ known.contains($0.uuidString) }) else { throw LibraryArchiveError.invalid("同步排序记录重复。") }
        }
        for key in state.home.keys {
            let parts = key.split(separator: ":", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count), parts.count == 1 || MediaStatus(rawValue: String(parts[1])) != nil else { throw LibraryArchiveError.invalid("同步首页分类无效。") }
            if parts[0] != "unset" {
                let month = parts[0].split(separator: "-", omittingEmptySubsequences: false)
                guard month.count == 2, let year = Int(month[0]), let number = Int(month[1]), (1...9999).contains(year), (1...12).contains(number), String(parts[0]) == "\(year)-\(number)" else { throw LibraryArchiveError.invalid("同步首页年月无效。") }
            }
        }
        for key in state.ranking.keys { guard let rating = Int(key), (0...10).contains(rating) else { throw LibraryArchiveError.invalid("同步排序评分无效。") } }
    }
    /// Returns bytes only for changed/new attachments. Existing fingerprints avoid reopening images.
    static func track(_ snapshot: LibraryDocument, old: LibrarySyncState?, folder: URL, strict: Bool, forceRead: Bool = false, markNewAtCommit: Bool = false, bytesRead: inout Int) throws -> (state: LibrarySyncState, payloads: [String: Data]) {
        let document = try LibraryDocument.decode(snapshot.encoded())
        var state = old ?? LibrarySyncState(), payloads: [String: Data] = [:]
        let stamp = SyncStamp.fresh(after: Array(state.records.values).flatMap { Array($0.fields.values) + [$0.restoredAfter].compactMap { $0 } } + state.deletions.values.map(\.stamp) + state.home.values.map(\.stamp) + state.ranking.values.map(\.stamp))
        let drafts = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        for entry in document.entries {
            let id = entry.id.uuidString, previous = state.records[id]
            var files: [String: SyncFingerprint] = [:]
            for kind in AttachmentKind.allCases where entry.attachments[kind] != nil {
                let path = kind.path(for: entry.id)
                var data = drafts[entry.id]?[kind]
                let source = snapshot.attachmentDirectory ?? folder
                if data == nil, !forceRead, source.standardizedFileURL == folder.standardizedFileURL, let file = previous?.files[kind.rawValue] {
                    let url = folder.appendingPathComponent(path)
                    if FileManager.default.fileExists(atPath: url.path) {
                        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw LibraryArchiveError.invalid("附件不是可读取的文件。") }
                        files[kind.rawValue] = file; continue
                    }
                    if strict { throw LibraryArchiveError.invalid("缺少作品附件。") }
                    continue
                }
                if data == nil {
                    let url = source.appendingPathComponent(path)
                    if FileManager.default.fileExists(atPath: url.path) { data = try LibraryArchive.readCoordinated(url); bytesRead += data!.count }
                }
                guard let data else {
                    if strict { throw LibraryArchiveError.invalid("\(entry.title)：缺少\(kind.rawValue)附件。") }
                    continue
                }
                files[kind.rawValue] = SyncFingerprint(data)
                if previous?.files[kind.rawValue] != files[kind.rawValue] || !FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path) { payloads[path] = data }
            }
            var record = try SyncFields.seed(entry, files: files)
            if let previous {
                let before = try SyncFields.values(previous), after = try SyncFields.values(record)
                record.fields = previous.fields; record.restoredAfter = previous.restoredAfter
                for field in SyncFields.names where before[field] != after[field] { record.fields[field] = stamp }
            }
            if previous == nil && markNewAtCommit {
                record.fields = Dictionary(uniqueKeysWithValues: SyncFields.names.map { ($0, stamp) })
            }
            // An intentional re-add after a deletion is a resurrection, not an absent-file inference.
            if let deletion = state.deletions[id], previous == nil { record.restoredAfter = SyncStamp.fresh(after: [deletion.stamp, stamp]) }
            state.records[id] = record
        }
        let present = Set(document.entries.map { $0.id.uuidString })
        for (id, record) in state.records where !present.contains(id) {
            state.deletions[id] = SyncDeletion(stamp: stamp, basis: record.fields); state.records[id] = nil
        }
        let orders = LibrarySyncMerger.orders(document)
        func update(_ current: [String: [UUID]], _ prior: inout [String: SyncOrder]) {
            for key in Set(current.keys).union(prior.keys) {
                let ids = current[key] ?? []
                if prior[key]?.ids != ids {
                    let initial = SyncStamp(date: document.entries.map(\.updatedAt).max() ?? Date(timeIntervalSince1970: 0), operation: "seed:" + SyncCoding.hash(Data(ids.map(\.uuidString).joined(separator: ",").utf8)))
                    prior[key] = SyncOrder(ids: ids, stamp: old == nil ? initial : stamp)
                }
            }
        }
        update(orders.home, &state.home); update(orders.ranking, &state.ranking)
        state.libraryHash = SyncCoding.hash(try document.encoded())
        return (state, payloads)
    }
    static func commitLocal(_ snapshot: LibraryDocument, to folder: URL, replacingUnreadable: Bool = false) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try LibraryArchive.withTransaction(in: folder) {
            let previous: SyncEndpoint
            var orphaned = Set<String>()
            do { previous = try read(from: folder, empty: LibraryDocument(), strict: false) }
            catch {
                guard replacingUnreadable else { throw error }
                // Explicit restore has already backed up the unreadable library. Do not
                // interpret unknown old bytes as sync history or silently repair them.
                previous = SyncEndpoint(document: LibraryDocument(), state: LibrarySyncState(), folder: folder, version: try version(in: folder))
                if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) {
                    for case let file as URL in enumerator {
                        let path = String(file.path.dropFirst(folder.path.count + 1))
                        if LibraryFileTransaction.managed(path), path != LibraryFiles.libraryFileName, path != LibrarySyncState.fileName { orphaned.insert(path) }
                    }
                }
            }
            var bytes = 0
            let tracked = try track(snapshot, old: previous.state, folder: folder, strict: false, markNewAtCommit: previous.version.library != nil, bytesRead: &bytes)
            var writes = tracked.payloads
            let json = try snapshot.encoded(), manifest = try SyncCoding.encode(tracked.state)
            if previous.version.library != SyncCoding.hash(json) { writes[LibraryFiles.libraryFileName] = json }
            if previous.version.manifest != SyncCoding.hash(manifest) { writes[LibrarySyncState.fileName] = manifest }
            let oldPaths = attachmentPaths(previous.document), newPaths = attachmentPaths(snapshot)
            try LibraryFileTransaction.commit(writes: writes, deleting: oldPaths.union(orphaned).subtracting(newPaths), to: folder, expected: previous.version)
        }
    }
    /// A backup retains the exact sync history, rather than inventing new clocks.
    static func copyArchive(from sourceFolder: URL, to targetFolder: URL) throws {
        let source = try read(from: sourceFolder)
        try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        var empty = LibraryDocument(); empty.libraryID = source.document.libraryID
        let target = try read(from: targetFolder, empty: empty)
        let snapshot = SyncMerge(document: source.document, state: source.state, conflicts: [])
        var cache: [String: Data] = [:], bytes = 0
        let files = try changes(snapshot, destination: target, sources: [source], cache: &cache, bytesRead: &bytes)
        guard try version(in: sourceFolder) == source.version else { throw LibrarySyncError.changed }
        try LibraryFileTransaction.commit(writes: files.writes, deleting: files.deleting, to: targetFolder, expected: target.version)
    }
    static func attachmentPaths(_ document: LibraryDocument) -> Set<String> {
        Set(document.entries.flatMap { entry in AttachmentKind.allCases.filter { entry.attachments[$0] != nil }.map { $0.path(for: entry.id) } })
    }
    static func changes(_ merged: SyncMerge, destination: SyncEndpoint, sources: [SyncEndpoint], cache: inout [String: Data], bytesRead: inout Int) throws -> SyncFileChanges {
        var result = SyncFileChanges()
        for record in merged.state.records.values {
            for kind in AttachmentKind.allCases where record.entry.attachments[kind] != nil {
                guard let fingerprint = record.files[kind.rawValue] else { throw LibraryArchiveError.invalid("作品图片没有可用摘要。") }
                let path = kind.path(for: record.entry.id)
                if destination.state.records[record.entry.id.uuidString]?.files[kind.rawValue] == fingerprint,
                   FileManager.default.fileExists(atPath: destination.folder.appendingPathComponent(path).path) { result.skipped += 1; continue }
                let cacheKey = kind.rawValue + ":" + fingerprint.sha256
                var data = cache[cacheKey]
                if data == nil {
                    outer: for source in sources {
                        for original in source.state.records.values where original.files[kind.rawValue] == fingerprint {
                            let url = source.folder.appendingPathComponent(kind.path(for: original.entry.id))
                            guard FileManager.default.fileExists(atPath: url.path) else { continue }
                            let bytes = try LibraryArchive.readCoordinated(url); bytesRead += bytes.count
                            guard SyncFingerprint(bytes) == fingerprint else { throw LibraryArchiveError.invalid("\(original.entry.title)：图片摘要校验失败，未同步。") }
                            data = bytes; cache[cacheKey] = bytes; break outer
                        }
                    }
                }
                guard let data else { throw LibraryArchiveError.invalid("\(record.entry.title)：找不到完整的\(kind.rawValue)附件。") }
                result.writes[path] = data; result.attachments += 1; result.bytes += data.count
            }
        }
        let json = try merged.document.encoded(), manifest = try SyncCoding.encode(merged.state)
        if destination.version.library != SyncCoding.hash(json) { result.writes[LibraryFiles.libraryFileName] = json }
        if destination.version.manifest != SyncCoding.hash(manifest) { result.writes[LibrarySyncState.fileName] = manifest }
        result.deleting = attachmentPaths(destination.document).subtracting(attachmentPaths(merged.document))
        return result
    }
}
