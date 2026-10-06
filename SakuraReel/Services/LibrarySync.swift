import Foundation
import CryptoKit

/// Full precision dates are retained in the sidecar (the library's ISO dates are unchanged).
struct SyncStamp: Codable, Hashable, Comparable, Sendable {
    var date: Date
    var operation: String
    static func < (a: Self, b: Self) -> Bool {
        a.date == b.date ? a.operation < b.operation : a.date < b.date
    }
    static func fresh(after stamps: [Self] = []) -> Self {
        Self(date: max(Date(), (stamps.map(\.date).max() ?? .distantPast).addingTimeInterval(0.001)), operation: UUID().uuidString)
    }
}
struct SyncFingerprint: Codable, Hashable, Sendable {
    var sha256: String
    var size: Int
    init(_ data: Data) { sha256 = SyncCoding.hash(data); size = data.count }
}
struct SyncRecord: Codable, Equatable, Sendable {
    var entry: LibraryEntry
    var fields: [String: SyncStamp]
    var files: [String: SyncFingerprint]
    var restoredAfter: SyncStamp?
}
struct SyncDeletion: Codable, Equatable, Sendable {
    var stamp: SyncStamp
    var basis: [String: SyncStamp]
}
struct SyncOrder: Codable, Equatable, Sendable {
    var ids: [UUID]
    var stamp: SyncStamp
}
struct LibrarySyncState: Codable, Equatable, Sendable {
    static let fileName = "SakuraReelSync.json"
    var version = 1
    var libraryHash = ""
    var records: [String: SyncRecord] = [:]
    var deletions: [String: SyncDeletion] = [:]
    var aliases: [String: String] = [:]
    var home: [String: SyncOrder] = [:]
    var ranking: [String: SyncOrder] = [:]
}
struct SyncEndpoint: Sendable {
    var document: LibraryDocument
    var state: LibrarySyncState
    var folder: URL
    /// Exact bytes of both metadata files; nil denotes a new, empty target.
    var version: SyncVersion
    var indexedBytes = 0
}
struct SyncVersion: Codable, Equatable, Sendable {
    var library: String?
    var manifest: String?
}
struct SyncDeleteConflict: Identifiable, Sendable {
    var id: String
    var entry: LibraryEntry
    var deletedAt: Date
}
struct SyncMerge: Sendable {
    var document: LibraryDocument
    var state: LibrarySyncState
    var conflicts: [SyncDeleteConflict]
}
enum SyncCoding {
    static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ bytes: Data) throws -> T { try JSONDecoder().decode(type, from: bytes) }
}

/// Each property is a register. Compound identities/months and arrays stay atomic.
enum SyncFields {
    static let metadata = ["originalTitle", "seasonTitle", "overview", "releaseDate", "genres", "remoteStatus", "runtimeMinutes", "episodeCount", "tmdbRating", "homepage", "posterPath", "backdropPath", "logoPath", "companies", "cast", "crew", "seasons", "episodes"]
    static let personal = ["status", "watchedAt", "rating", "review", "playURL"]
    static let names = ["title", "source", "metadataPresent"] + personal.map { "personal." + $0 } + metadata.map { "metadata." + $0 } + AttachmentKind.allCases.map { "file." + $0.rawValue }
    static func values(_ record: SyncRecord) throws -> [String: Data] {
        let root = try JSONSerialization.jsonObject(with: LibraryCoding.encoder.encode(record.entry)) as! [String: Any]
        let work = root["work"] as! [String: Any]
        let meta = work["metadata"] as? [String: Any] ?? [:]
        let person = root["personal"] as! [String: Any]
        var raw: [String: Any] = ["title": work["title"]!, "source": root["source"] ?? NSNull(), "metadataPresent": work["metadata"] != nil]
        for key in personal { raw["personal." + key] = person[key] ?? NSNull() }
        for key in metadata { raw["metadata." + key] = meta[key] ?? NSNull() }
        for kind in AttachmentKind.allCases {
            raw["file." + kind.rawValue] = record.files[kind.rawValue].map { ["sha256": $0.sha256, "size": $0.size] as [String: Any] } ?? NSNull()
        }
        return try raw.mapValues { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]) }
    }
    static func entry(_ fields: [String: Data], id: UUID, created: Date, updated: Date) throws -> LibraryEntry {
        func value(_ key: String) throws -> Any { try JSONSerialization.jsonObject(with: fields[key]!, options: .fragmentsAllowed) }
        var work: [String: Any] = ["title": try value("title")]
        var meta: [String: Any] = [:], person: [String: Any] = [:], attachments: [String: Any] = [:]
        for key in personal { let v = try value("personal." + key); if !(v is NSNull) { person[key] = v } }
        for key in metadata { let v = try value("metadata." + key); if !(v is NSNull) { meta[key] = v } }
        // A nonempty merged metadata field survives a concurrent metadata removal.
        if (try value("metadataPresent") as? Bool) == true || !meta.isEmpty { work["metadata"] = meta }
        for kind in AttachmentKind.allCases where !(try value("file." + kind.rawValue) is NSNull) { attachments[kind.rawValue] = kind.format }
        let dates = ISO8601DateFormatter()
        var root: [String: Any] = ["id": id.uuidString, "work": work, "personal": person, "attachments": attachments, "createdAt": dates.string(from: created), "updatedAt": dates.string(from: max(created, updated))]
        let source = try value("source"); if !(source is NSNull) { root["source"] = source }
        return try LibraryCoding.decoder.decode(LibraryEntry.self, from: JSONSerialization.data(withJSONObject: root, options: .sortedKeys))
    }
    static func seed(_ entry: LibraryEntry, files: [String: SyncFingerprint]) throws -> SyncRecord {
        var result = SyncRecord(entry: entry, fields: [:], files: files)
        for (field, bytes) in try values(result) {
            result.fields[field] = SyncStamp(date: entry.updatedAt, operation: "seed:" + SyncCoding.hash(bytes))
        }
        return result
    }
    static func merge(_ a: SyncRecord, _ b: SyncRecord, id: UUID) throws -> SyncRecord {
        let av = try values(a), bv = try values(b)
        var values: [String: Data] = [:], clocks: [String: SyncStamp] = [:], files: [String: SyncFingerprint] = [:]
        for name in names {
            let chooseB = a.fields[name]! < b.fields[name]! || (a.fields[name]! == b.fields[name]! && av[name]!.lexicographicallyPrecedes(bv[name]!))
            values[name] = chooseB ? bv[name]! : av[name]!
            clocks[name] = chooseB ? b.fields[name]! : a.fields[name]!
            if name.hasPrefix("file.") {
                let kind = String(name.dropFirst(5)); files[kind] = (chooseB ? b : a).files[kind]
            }
        }
        let entry = try entry(values, id: id, created: min(a.entry.createdAt, b.entry.createdAt), updated: max(a.entry.updatedAt, b.entry.updatedAt))
        return SyncRecord(entry: entry, fields: clocks, files: files, restoredAfter: [a.restoredAfter, b.restoredAfter].compactMap { $0 }.max())
    }
}

enum LibrarySyncMerger {
    static func homeKey(_ month: YearMonth?) -> String { month.map { "\($0.year)-\($0.month)" } ?? "unset" }
    static func orders(_ document: LibraryDocument) -> (home: [String: [UUID]], ranking: [String: [UUID]]) {
        var home: [String: [UUID]] = [:]
        let byID = Dictionary(uniqueKeysWithValues: document.entries.map { ($0.id, $0) })
        for group in document.homeGroups {
            let key = homeKey(group.month); home[key] = group.ids
            for status in MediaStatus.allCases { home[key + ":" + status.rawValue] = group.ids.filter { byID[$0]?.status == status } }
        }
        return (home, Dictionary(uniqueKeysWithValues: document.rankingGroups.map { (String($0.rating), $0.ids) }))
    }
    static func merge(_ a: SyncEndpoint, _ b: SyncEndpoint, choices: [String: Bool] = [:]) throws -> SyncMerge {
        // Union identities and persisted aliases. The smallest UUID is the canonical ID.
        var parents: [String: String] = [:]
        func root(_ key: String) -> String {
            var key = key
            while let next = parents[key], next != key { key = next }
            return key
        }
        func join(_ a: String, _ b: String) { let x = root(a), y = root(b); if x != y { parents[max(x, y)] = min(x, y) } }
        for state in [a.state, b.state] { for (old, new) in state.aliases { join(old, new) } }
        var identities: [TMDbIdentity: String] = [:]
        for record in (Array(a.state.records.values) + Array(b.state.records.values)).sorted(by: { $0.entry.id.uuidString < $1.entry.id.uuidString }) {
            if let source = record.entry.source {
                let id = record.entry.id.uuidString
                if let old = identities[source.tmdb] { join(id, old) } else { identities[source.tmdb] = id }
            }
        }
        var state = LibrarySyncState()
        let keys = Set(a.state.records.keys).union(b.state.records.keys).union(a.state.deletions.keys).union(b.state.deletions.keys).union(parents.keys)
        for key in keys where root(key) != key { state.aliases[key] = root(key) }
        for endpoint in [a, b] {
            for (key, value) in endpoint.state.records {
                let id = root(key); var value = value; value.entry.id = UUID(uuidString: id)!
                if let old = state.records[id] { state.records[id] = try SyncFields.merge(old, value, id: value.entry.id) }
                else { state.records[id] = value }
            }
            for (key, deletion) in endpoint.state.deletions {
                let id = root(key)
                if let old = state.deletions[id] {
                    var merged = old.stamp < deletion.stamp ? deletion : old
                    for (field, stamp) in (old.stamp < deletion.stamp ? old : deletion).basis {
                        merged.basis[field] = max(merged.basis[field] ?? stamp, stamp)
                    }
                    state.deletions[id] = merged
                } else { state.deletions[id] = deletion }
            }
        }
        var conflicts: [SyncDeleteConflict] = []
        for id in state.deletions.keys.sorted() {
            guard let record = state.records[id], let deletion = state.deletions[id] else { continue }
            if let restored = record.restoredAfter, restored > deletion.stamp { continue }
            let changed = record.fields.contains { field, stamp in deletion.basis[field].map { stamp > $0 } ?? true }
            if changed {
                guard let keep = choices[id] else {
                    conflicts.append(SyncDeleteConflict(id: id, entry: record.entry, deletedAt: deletion.stamp.date)); continue
                }
                let resolution = SyncStamp.fresh(after: Array(record.fields.values) + [deletion.stamp])
                if keep { state.records[id]?.restoredAfter = resolution }
                else { state.deletions[id] = SyncDeletion(stamp: resolution, basis: record.fields); state.records[id] = nil }
            } else { state.records[id] = nil }
        }
        func combine(_ lhs: [String: SyncOrder], _ rhs: [String: SyncOrder]) -> [String: SyncOrder] {
            var result = lhs
            for (key, order) in rhs where result[key] == nil || result[key]!.stamp < order.stamp || (result[key]!.stamp == order.stamp && result[key]!.ids.map(\.uuidString).joined() < order.ids.map(\.uuidString).joined()) { result[key] = order }
            for key in result.keys { result[key]!.ids = unique(result[key]!.ids.map { UUID(uuidString: root($0.uuidString))! }) }
            return result
        }
        state.home = combine(a.state.home, b.state.home); state.ranking = combine(a.state.ranking, b.state.ranking)
        let entries = state.records.values.map(\.entry).sorted { $0.id.uuidString < $1.id.uuidString }
        var document = LibraryDocument(items: entries.map { MediaItem(entry: $0) })
        func fresh(_ endpoint: SyncEndpoint) -> Bool { endpoint.document.revision == 0 && endpoint.document.entries.isEmpty && endpoint.state.deletions.isEmpty }
        if fresh(a) && !fresh(b) { document.libraryID = b.document.libraryID }
        else if fresh(b) && !fresh(a) { document.libraryID = a.document.libraryID }
        else { document.libraryID = min(a.document.libraryID.uuidString, b.document.libraryID.uuidString) == a.document.libraryID.uuidString ? a.document.libraryID : b.document.libraryID }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for index in document.homeGroups.indices {
            let group = document.homeGroups[index], key = homeKey(group.month), members = Set(group.ids)
            let selected = state.home[key]?.ids ?? []
            var ids = selected.filter { members.contains($0) }
            let missing = group.ids.filter { !ids.contains($0) }.sorted {
                let x = byID[$0]!, y = byID[$1]!
                return x.createdAt == y.createdAt ? $0.uuidString < $1.uuidString : x.createdAt > y.createdAt
            }
            // New entries precede the selected order; moved entries append to the new month.
            let known = Set(state.home.values.flatMap(\.ids))
            ids = missing.filter { !known.contains($0) } + ids + missing.filter { known.contains($0) }
            for status in MediaStatus.allCases {
                let slots = ids.indices.filter { byID[ids[$0]]?.status == status }
                let wanted = Set(slots.map { ids[$0] })
                var category = (state.home[key + ":" + status.rawValue]?.ids ?? []).filter { wanted.contains($0) }
                let extras = slots.map { ids[$0] }.filter { !category.contains($0) }
                category = extras.filter { !known.contains($0) } + category + extras.filter { known.contains($0) }
                for (slot, id) in zip(slots, category) { ids[slot] = id }
            }
            document.homeGroups[index].ids = ids
        }
        document.homeGroups.sort { ( $0.month ?? YearMonth(year: 0, month: 0)) > ($1.month ?? YearMonth(year: 0, month: 0)) }
        let defaults = MediaSort.rankingDefaultSorted(document.items, homeOrder: document.homeOrder).map(\.id)
        for key in state.ranking.keys.sorted() {
            guard let rating = Int(key) else { throw LibraryArchiveError.invalid("同步排序评分无效。") }
            guard !state.ranking[key]!.ids.isEmpty else { continue }
            let members = Set(entries.filter { $0.rating == rating }.map(\.id))
            guard !members.isEmpty else { continue }
            var ids = state.ranking[key]!.ids.filter { members.contains($0) }
            for id in defaults where members.contains(id) && !ids.contains(id) {
                let position = defaults.firstIndex(of: id)!
                let insertion = ids.firstIndex { defaults.firstIndex(of: $0)! > position } ?? ids.count
                ids.insert(id, at: insertion)
            }
            document.rankingGroups.append(RankingOrderGroup(rating: rating, ids: ids))
        }
        func content(_ doc: LibraryDocument) throws -> Data { var doc = doc; doc.revision = 0; return try doc.encoded() }
        document.revision = max(a.document.revision, b.document.revision)
        let desiredContent = try content(document)
        func changed(_ endpoint: SyncEndpoint) throws -> Bool {
            let dataChanged = try desiredContent != content(endpoint.document)
            let imageChanged = state.records.contains { id, record in endpoint.state.records[id]?.files != record.files }
            return dataChanged || imageChanged
        }
        // A lower counter can adopt the existing maximum. Equal counters with different
        // content must advance, because visible image/detail tasks use this revision.
        let needsFreshRevision = try (changed(a) && a.document.revision == document.revision) || (changed(b) && b.document.revision == document.revision)
        if needsFreshRevision {
            guard document.revision < UInt64.max else { throw LibraryArchiveError.invalid("资料库版本计数已达上限。") }
            document.revision += 1
        }
        let effective = orders(document)
        let initialStamp = SyncStamp(date: entries.map(\.updatedAt).max() ?? Date(timeIntervalSince1970: 0), operation: "merged-order")
        for key in Set(state.home.keys).union(effective.home.keys) {
            state.home[key] = SyncOrder(ids: effective.home[key] ?? [], stamp: state.home[key]?.stamp ?? initialStamp)
        }
        for key in Set(state.ranking.keys).union(effective.ranking.keys) {
            state.ranking[key] = SyncOrder(ids: effective.ranking[key] ?? [], stamp: state.ranking[key]?.stamp ?? initialStamp)
        }
        state.libraryHash = SyncCoding.hash(try document.encoded())
        try LibraryValidator.validate(document)
        return SyncMerge(document: document, state: state, conflicts: conflicts)
    }
    private static func unique(_ ids: [UUID]) -> [UUID] { var seen = Set<UUID>(); return ids.filter { seen.insert($0).inserted } }
}
