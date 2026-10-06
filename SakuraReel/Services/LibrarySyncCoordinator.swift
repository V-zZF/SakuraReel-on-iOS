import Foundation

struct LibrarySyncPreparation: Identifiable, Sendable {
    let id = UUID()
    var local: SyncEndpoint
    var remote: SyncEndpoint
    var merged: SyncMerge
    var resumed: Bool = false
    var startedAt = Date()
}
struct LibrarySyncReport: Sendable {
    var added: Int
    var modified: Int
    var deleted: Int
    var transferred: Int
    var skipped: Int
    var readBytes: Int
    var writtenBytes: Int
    var elapsed: TimeInterval
    var unchanged: Bool
    var description: String {
        if unchanged { return "已是最新。\n跳过 \(skipped) 个图片文件，图片读取和写入均为 0 字节。" }
        return "新增 \(added) 部 · 修改 \(modified) 部 · 删除 \(deleted) 部\n两端共更新 \(transferred) 个图片文件 · 跳过 \(skipped) 个\n图片读取 \(ByteCountFormatter.string(fromByteCount: Int64(readBytes), countStyle: .file)) · 写入 \(ByteCountFormatter.string(fromByteCount: Int64(writtenBytes), countStyle: .file))（含变化文件的回滚备份）\n用时 \(String(format: "%.1f", elapsed)) 秒。"
    }
}

/// Synchronous disk work is called only by LibraryStorage, never by the main actor.
enum LibrarySyncCoordinator {
    struct Checkpoint: Codable {
        var document: LibraryDocument
        var state: LibrarySyncState
        var local: SyncVersion
        var remote: SyncVersion
    }
    struct Baseline: Codable {
        var document: LibraryDocument
        var state: LibrarySyncState
        var completedAt: Date
    }
    private static func validate(document: LibraryDocument, state: LibrarySyncState) throws {
        try LibraryValidator.validate(document); try LibrarySyncDisk.validate(state)
        guard state.libraryHash == SyncCoding.hash(try document.encoded()),
              Set(state.records.keys) == Set(document.entries.map { $0.id.uuidString }),
              document.entries.allSatisfy({ state.records[$0.id.uuidString]?.entry == $0 }) else { throw LibraryArchiveError.invalid("同步检查点或基线不一致。") }
    }
    static func bookkeeping(local: URL, remote: URL) -> URL {
        // Scope by sandbox and authorized folder; this also isolates test repositories.
        let key = SyncCoding.hash(Data((local.standardizedFileURL.path + "\n" + remote.standardizedFileURL.path).utf8))
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SakuraReel/Sync/" + key, isDirectory: true)
    }
    static func prepare(local: URL, remote: URL) throws -> LibrarySyncPreparation {
        let started = Date()
        guard local.resolvingSymlinksInPath().standardizedFileURL != remote.resolvingSymlinksInPath().standardizedFileURL else { throw LibraryArchiveError.invalid("同步文件夹不能是当前资料库目录，请选择另一个专用文件夹。") }
        let baselineURL = bookkeeping(local: local, remote: remote).appendingPathComponent("baseline.json")
        var baseline: Baseline?
        if FileManager.default.fileExists(atPath: baselineURL.path) {
            baseline = try SyncCoding.decode(Baseline.self, Data(contentsOf: baselineURL))
            try validate(document: baseline!.document, state: baseline!.state)
        }
        let a = try LibrarySyncDisk.read(from: local, recovering: baseline?.state)
        var empty = LibraryDocument(); empty.libraryID = a.document.libraryID
        let b = try LibrarySyncDisk.read(from: remote, empty: empty, recovering: baseline?.state)
        let pending = bookkeeping(local: local, remote: remote).appendingPathComponent("pending.json")
        if FileManager.default.fileExists(atPath: pending.path) {
            let checkpoint = try SyncCoding.decode(Checkpoint.self, Data(contentsOf: pending))
            try validate(document: checkpoint.document, state: checkpoint.state)
            let intended = try SyncVersion(library: SyncCoding.hash(checkpoint.document.encoded()), manifest: SyncCoding.hash(SyncCoding.encode(checkpoint.state)))
            if [checkpoint.local, intended].contains(a.version), [checkpoint.remote, intended].contains(b.version) {
                return LibrarySyncPreparation(local: a, remote: b, merged: SyncMerge(document: checkpoint.document, state: checkpoint.state, conflicts: []), resumed: true, startedAt: started)
            }
            // A user edited after interruption: compare the current endpoints afresh.
        }
        return LibrarySyncPreparation(local: a, remote: b, merged: try LibrarySyncMerger.merge(a, b), startedAt: started)
    }
    static func apply(_ preparation: LibrarySyncPreparation, choices: [String: Bool], progress: @Sendable (String) -> Void = { _ in }, failLocalAfterInstall: Int? = nil) throws -> (LibraryDocument, LibrarySyncReport) {
        let a = preparation.local, b = preparation.remote
        guard try LibrarySyncDisk.version(in: a.folder) == a.version, try LibrarySyncDisk.version(in: b.folder) == b.version else { throw LibrarySyncError.changed }
        let merged = preparation.resumed ? preparation.merged : try LibrarySyncMerger.merge(a, b, choices: choices)
        guard merged.conflicts.isEmpty else { throw LibraryArchiveError.invalid("请先处理所有删除与修改冲突。") }
        progress("校验变化图片…")
        var cache: [String: Data] = [:], readBytes = a.indexedBytes + b.indexedBytes
        let localChanges = try LibrarySyncDisk.changes(merged, destination: a, sources: [a, b], cache: &cache, bytesRead: &readBytes)
        let remoteChanges = try LibrarySyncDisk.changes(merged, destination: b, sources: [b, a], cache: &cache, bytesRead: &readBytes)
        // Both sets of attachment bytes are ready before either endpoint is modified.
        guard try LibrarySyncDisk.version(in: a.folder) == a.version, try LibrarySyncDisk.version(in: b.folder) == b.version else { throw LibrarySyncError.changed }
        let bookkeeping = bookkeeping(local: a.folder, remote: b.folder)
        try FileManager.default.createDirectory(at: bookkeeping, withIntermediateDirectories: true)
        let pending = bookkeeping.appendingPathComponent("pending.json")
        try SyncCoding.encode(Checkpoint(document: merged.document, state: merged.state, local: a.version, remote: b.version)).write(to: pending, options: .atomic)
        progress("提交同步文件夹（\(remoteChanges.attachments) 个图片文件）…")
        let remoteIO = try LibraryFileTransaction.commit(writes: remoteChanges.writes, deleting: remoteChanges.deleting, to: b.folder, expected: b.version)
        progress("提交本机（\(localChanges.attachments) 个图片文件）…")
        let localIO = try LibraryFileTransaction.commit(writes: localChanges.writes, deleting: localChanges.deleting, to: a.folder, expected: a.version, failAfterInstall: failLocalAfterInstall)
        let intended = try SyncVersion(library: SyncCoding.hash(merged.document.encoded()), manifest: SyncCoding.hash(SyncCoding.encode(merged.state)))
        guard try LibrarySyncDisk.version(in: a.folder) == intended, try LibrarySyncDisk.version(in: b.folder) == intended else { throw LibrarySyncError.changed }
        // Advance only after both installations succeeded. A remaining checkpoint is safe to retry.
        try SyncCoding.encode(Baseline(document: merged.document, state: merged.state, completedAt: Date())).write(to: bookkeeping.appendingPathComponent("baseline.json"), options: .atomic)
        try FileManager.default.removeItem(at: pending)
        func canonical(_ id: String) -> String {
            var id = id
            while let next = merged.state.aliases[id] { id = next }
            return id
        }
        let localBefore = Dictionary(grouping: a.state.records.values, by: { canonical($0.entry.id.uuidString) })
        let remoteBefore = Dictionary(grouping: b.state.records.values, by: { canonical($0.entry.id.uuidString) })
        let new = merged.state.records
        let report = LibrarySyncReport(added: new.keys.filter { localBefore[$0] == nil || remoteBefore[$0] == nil }.count,
                                      modified: new.keys.filter { id in
                                          guard let lhs = localBefore[id], let rhs = remoteBefore[id] else { return false }
                                          return (lhs + rhs).contains { before in
                                              var entry = before.entry; entry.id = new[id]!.entry.id
                                              return entry != new[id]!.entry || before.files != new[id]!.files
                                          }
                                      }.count,
                                      deleted: Set(localBefore.keys).union(remoteBefore.keys).subtracting(new.keys).count,
                                      transferred: localChanges.attachments + remoteChanges.attachments,
                                      skipped: localChanges.skipped + remoteChanges.skipped,
                                      readBytes: readBytes + localIO.readBytes + remoteIO.readBytes, writtenBytes: localIO.writtenBytes + remoteIO.writtenBytes,
                                      elapsed: Date().timeIntervalSince(preparation.startedAt),
                                      unchanged: localChanges.writes.isEmpty && remoteChanges.writes.isEmpty && localChanges.deleting.isEmpty && remoteChanges.deleting.isEmpty && readBytes == 0)
        return (merged.document, report)
    }
}
