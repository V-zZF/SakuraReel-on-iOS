import Foundation

struct YearMonth: Codable, Hashable, Comparable, Sendable {
    var year: Int
    var month: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.year == rhs.year ? lhs.month < rhs.month : lhs.year < rhs.year
    }
}

struct PersonalRecord: Codable, Hashable, Sendable {
    var status: MediaStatus
    var watchedAt: YearMonth?
    var rating: Int
    var review: String?
    var playURL: String?
}

struct WorkDetails: Codable, Hashable, Sendable {
    var title: String
    var metadata: MediaMetadata?
}

enum AttachmentKind: String, Codable, CaseIterable, Sendable {
    case poster, backdrop, logo
    var format: String { self == .logo ? "png" : "jpg" }
    func path(for id: UUID) -> String {
        self == .poster ? "Posters/\(id.uuidString).jpg" : "Artwork/\(id.uuidString)/\(rawValue).\(format)"
    }
}
struct AttachmentManifest: Codable, Hashable, Sendable {
    var poster: String?
    var backdrop: String?
    var logo: String?
    subscript(_ kind: AttachmentKind) -> String? {
        get { switch kind { case .poster: poster; case .backdrop: backdrop; case .logo: logo } }
        set { switch kind { case .poster: poster = newValue; case .backdrop: backdrop = newValue; case .logo: logo = newValue } }
    }
}

/// Persisted entry. Attachments are descriptions only; bytes belong to a separate draft.
struct LibraryEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var work: WorkDetails
    var personal: PersonalRecord
    var source: MediaSource?
    var attachments: AttachmentManifest
    var createdAt: Date
    var updatedAt: Date
    var title: String { get { work.title } set { work.title = newValue } }
    var metadata: MediaMetadata? { get { work.metadata } set { work.metadata = newValue } }
    var status: MediaStatus { get { personal.status } set { personal.status = newValue } }
    var watchYear: Int? { personal.watchedAt?.year }
    var watchMonth: Int? { personal.watchedAt?.month }
    var rating: Int { get { personal.rating } set { personal.rating = newValue } }
    var review: String? { get { personal.review } set { personal.review = newValue } }
    var playURL: String? { get { personal.playURL } set { personal.playURL = newValue } }
}

/// Unsaved editing or transfer value; repository lists keep the payload empty.
@dynamicMemberLookup
struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    var entry: LibraryEntry
    var id: UUID { get { entry.id } set { entry.id = newValue } }
    var poster: Data? { didSet { entry.attachments.poster = poster == nil ? nil : "jpg" } }
    var backdrop: Data? { didSet { entry.attachments.backdrop = backdrop == nil ? nil : "jpg" } }
    var logo: Data? { didSet { entry.attachments.logo = logo == nil ? nil : "png" } }
    subscript<Value>(dynamicMember path: WritableKeyPath<LibraryEntry, Value>) -> Value {
        get { entry[keyPath: path] }
        set { entry[keyPath: path] = newValue }
    }
    subscript<Value>(dynamicMember path: KeyPath<LibraryEntry, Value>) -> Value { entry[keyPath: path] }
    init(entry: LibraryEntry) { self.entry = entry }
    init(from decoder: Decoder) throws { entry = try LibraryEntry(from: decoder) }
    func encode(to encoder: Encoder) throws { try entry.encode(to: encoder) }
    init(id: UUID = UUID(), title: String, poster: Data? = nil, status: MediaStatus,
         watchedAt: YearMonth? = nil, rating: Int = 0,
         review: String? = nil, playURL: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(),
         source: MediaSource? = nil, metadata: MediaMetadata? = nil, backdrop: Data? = nil, logo: Data? = nil) {
        entry = LibraryEntry(id: id, work: WorkDetails(title: title, metadata: metadata),
            personal: PersonalRecord(status: status, watchedAt: watchedAt, rating: rating, review: review, playURL: playURL),
            source: source, attachments: AttachmentManifest(), createdAt: createdAt, updatedAt: updatedAt)
        entry.attachments = AttachmentManifest(poster: poster == nil ? nil : "jpg", backdrop: backdrop == nil ? nil : "jpg", logo: logo == nil ? nil : "png")
        self.poster = poster; self.backdrop = backdrop; self.logo = logo
    }
    subscript(_ kind: AttachmentKind) -> Data? {
        get { switch kind { case .poster: poster; case .backdrop: backdrop; case .logo: logo } }
        set { switch kind { case .poster: poster = newValue; case .backdrop: backdrop = newValue; case .logo: logo = newValue } }
    }
    var lightweight: Self {
        var copy = self
        copy.poster = nil; copy.backdrop = nil; copy.logo = nil
        copy.attachments = entry.attachments
        return copy
    }
}
