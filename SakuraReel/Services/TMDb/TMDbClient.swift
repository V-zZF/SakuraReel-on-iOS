//
//  TMDbClient.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import Foundation

/// Coalesce work while cancelling the producer when its last consumer leaves.
actor SharedTaskPool<Value: Sendable> {
    private struct Entry {
        let id: UUID
        let task: Task<Value, Error>
        var waiters: Set<UUID>
    }
    private var entries: [String: Entry] = [:]
    func value(for key: String, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let waiter = UUID()
        if entries[key] == nil {
            entries[key] = Entry(id: UUID(), task: Task { try await operation() }, waiters: [])
        }
        entries[key]!.waiters.insert(waiter)
        let entry = entries[key]!
        do {
            let result = try await withTaskCancellationHandler {
                try await entry.task.value
            } onCancel: {
                Task { await self.release(key, entryID: entry.id, waiter: waiter, cancelled: true) }
            }
            release(key, entryID: entry.id, waiter: waiter, cancelled: false)
            try Task.checkCancellation()
            return result
        } catch {
            release(key, entryID: entry.id, waiter: waiter, cancelled: true)
            throw error
        }
    }
    private func release(_ key: String, entryID: UUID, waiter: UUID, cancelled: Bool) {
        guard entries[key]?.id == entryID else { return }
        entries[key]?.waiters.remove(waiter)
        if entries[key]?.waiters.isEmpty == true {
            if cancelled { entries[key]?.task.cancel() }
            entries[key] = nil
        }
    }
    func cancelAll() {
        for entry in entries.values { entry.task.cancel() }
        entries.removeAll()
    }
}

struct TMDbConnection: Sendable, Equatable {
    var key: String
    var host = "api.themoviedb.org"
    var generation: UUID
}
enum TMDbError: LocalizedError, Equatable {
    case missingKey, authentication, network, rateLimited, notFound, decoding, server(Int), invalidProxy
    var errorDescription: String? {
        switch self {
        case .missingKey: String(localized: "请先在 TMDb 设置中保存 API Key。")
        case .authentication: String(localized: "API Key 无效或没有访问权限。")
        case .network: String(localized: "无法连接 TMDb，请检查网络或所选线路。")
        case .rateLimited: String(localized: "TMDb 请求过于频繁，请稍后重试。")
        case .notFound: String(localized: "TMDb 中已找不到此作品。")
        case .decoding: String(localized: "TMDb 返回的数据无法解析。")
        case .server(let code): String(localized: "TMDb 服务暂时不可用（\(code)）。")
        case .invalidProxy: String(localized: "请输入有效的 HTTPS API 主机，不包含路径、端口或鉴权信息。")
        }
    }
}
protocol TMDbHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
/// Never forward a credential through a cross-host redirect.
private final class TMDbRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.host == task.originalRequest?.url?.host && request.url?.scheme == "https" ? request : nil)
    }
}
final class TMDbURLTransport: TMDbHTTPTransport, Sendable {
    private let session = URLSession(configuration: .ephemeral, delegate: TMDbRedirectGuard(), delegateQueue: nil)
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TMDbError.network }
        return (data, response)
    }
}
struct TMDbRequestClient: Sendable {
    var transport: any TMDbHTTPTransport
    var sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    var now: @Sendable () -> Date = { Date() }

    static func validatedHost(_ proxy: String?) throws -> String {
        guard let proxy else { return "api.themoviedb.org" }
        let text = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TMDbError.invalidProxy }
        let url = URLComponents(string: text.contains("://") ? text : "https://" + text)
        guard let url, url.scheme == "https", let host = url.host, host.contains("."),
              url.port == nil, url.user == nil, url.password == nil,
              url.path.isEmpty || url.path == "/", url.query == nil, url.fragment == nil else { throw TMDbError.invalidProxy }
        return host.lowercased()
    }
    static func retryDelay(_ value: String?, now: Date, attempt: Int) -> TimeInterval {
        if let value, let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        if let value {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: value) { return max(0, date.timeIntervalSince(now)) }
        }
        return 0.5 * pow(2, Double(attempt))
    }
    func data(path: String, query: [URLQueryItem] = [], connection: TMDbConnection) async throws -> Data {
        guard !connection.key.isEmpty else { throw TMDbError.missingKey }
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = connection.host; parts.path = "/3" + path
        parts.queryItems = query + [URLQueryItem(name: "api_key", value: connection.key)]
        guard let url = parts.url else { throw TMDbError.invalidProxy }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        for attempt in 0...2 {
            try Task.checkCancellation()
            let data: Data
            let response: HTTPURLResponse
            do { (data, response) = try await transport.send(request) }
            catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                throw TMDbError.network
            }
            try Task.checkCancellation()
            switch response.statusCode {
            case 200..<300: return data
            case 401, 403: throw TMDbError.authentication
            case 404: throw TMDbError.notFound
            case 429:
                let delay = Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After"), now: now(), attempt: attempt)
                guard attempt < 2, delay <= 30 else { throw TMDbError.rateLimited }
                try await sleep(delay)
            default: throw TMDbError.server(response.statusCode)
            }
        }
        throw TMDbError.rateLimited
    }
    func decode<T: Decodable & Sendable>(_ type: T.Type, path: String, query: [URLQueryItem] = [], connection: TMDbConnection) async throws -> T {
        let data = try await data(path: path, query: query, connection: connection)
        do { return try JSONDecoder().decode(type, from: data) } catch { throw TMDbError.decoding }
    }
}

struct TMDbSearchResult: Identifiable, Hashable, Sendable {
    var source: MediaSource
    var title: String
    var date: String?
    var overview: String?
    var posterPath: String?
    var id: String { source.identity }
}
struct TMDbSearchPage: Sendable {
    var results: [TMDbSearchResult]
    var page: Int
    var totalPages: Int
}
protocol TMDbServing: Sendable {
    func search(_ query: String, type: TMDbMediaType, language: String, page: Int) async throws -> TMDbSearchPage
    func details(_ source: MediaSource) async throws -> TMDbImportDraft
    func imageURL(_ path: String, role: String, width: Int) async -> URL?
    func cachedImageURL(_ path: String, role: String, width: Int) async -> URL?
    func validate(_ connection: TMDbConnection) async throws
    func invalidateDetails() async
}
extension TMDbServing {
    func invalidateDetails() async {}
    func cachedImageURL(_ path: String, role: String, width: Int) async -> URL? {
        await imageURL(path, role: role, width: width)
    }
}

// Null-tolerant wire DTOs are intentionally separate from the editable local model.
struct TMDbRecord: Decodable, Sendable {
    var id: Int
    var title: String?
    var name: String?
    var original_title: String?
    var original_name: String?
    var overview: String?
    var release_date: String?
    var first_air_date: String?
    var air_date: String?
    var poster_path: String?
    var backdrop_path: String?
    var original_language: String?
    var status: String?
    var runtime: Int?
    var episode_run_time: [Int]?
    var number_of_episodes: Int?
    var vote_average: Double?
    var homepage: String?
    var genres: [Named]?
    var production_companies: [Company]?
    var seasons: [Part]?
    var episodes: [Part]?
    struct Named: Decodable, Sendable { var name: String }
    struct Company: Decodable, Sendable { var id: Int; var name: String; var logo_path: String? }
    struct Part: Decodable, Sendable {
        var id: Int; var name: String?; var overview: String?; var air_date: String?
        var season_number: Int?; var episode_number: Int?; var episode_count: Int?
        var poster_path: String?; var still_path: String?
        var local: MediaPart {
            MediaPart(id: id, number: season_number ?? episode_number ?? 0, title: name ?? "",
                      overview: overview, date: air_date, episodeCount: episode_count, imagePath: poster_path ?? still_path)
        }
    }
}
private struct WirePage: Decodable, Sendable {
    var page: Int; var total_pages: Int; var results: [TMDbRecord]
}
private struct WireImages: Decodable, Sendable {
    var posters: [Resource]?; var backdrops: [Resource]?; var logos: [Resource]?
    struct Resource: Decodable, Sendable {
        var file_path: String; var iso_639_1: String?; var vote_average: Double?
    }
}
private struct WireCredits: Decodable, Sendable {
    var cast: [Credit]?; var crew: [Credit]?
    struct Credit: Decodable, Sendable {
        var id: Int; var credit_id: String?; var name: String; var character: String?; var job: String?; var profile_path: String?
        var local: MediaCredit {
            MediaCredit(id: credit_id ?? "\(id):\(job ?? character ?? "")", name: name,
                        role: character ?? job ?? "", imagePath: profile_path)
        }
    }
}
private struct ImageConfiguration: Decodable, Sendable {
    var images: Images
    struct Images: Decodable, Sendable {
        var secure_base_url: String
        var poster_sizes: [String]; var backdrop_sizes: [String]; var logo_sizes: [String]
        var profile_sizes: [String]; var still_sizes: [String]
    }
    static let fallback = ImageConfiguration(images: Images(secure_base_url: "https://image.tmdb.org/t/p/",
        poster_sizes: ["w92", "w185", "w342", "w500", "w780", "original"],
        backdrop_sizes: ["w300", "w780", "w1280", "original"], logo_sizes: ["w185", "w500", "original"],
        profile_sizes: ["w185", "h632", "original"], still_sizes: ["w185", "w300", "original"]))
}

actor TMDbService: TMDbServing {
    private let client: TMDbRequestClient
    private let connection: @Sendable () async -> TMDbConnection
    private var configurations: [UUID: (ImageConfiguration, Date)] = [:]
    private let configTasks = SharedTaskPool<ImageConfiguration>()
    private var records: [String: (TMDbRecord, Date)] = [:]
    private let recordTasks = SharedTaskPool<TMDbRecord>()
    init(client: TMDbRequestClient = TMDbRequestClient(transport: TMDbURLTransport()),
         connection: @escaping @Sendable () async -> TMDbConnection) {
        self.client = client; self.connection = connection
    }
    func invalidateDetails() async { records.removeAll(); await recordTasks.cancelAll() }
    func validate(_ connection: TMDbConnection) async throws {
        _ = try await client.decode(ImageConfiguration.self, path: "/configuration", connection: connection)
    }
    func search(_ query: String, type: TMDbMediaType, language: String, page: Int) async throws -> TMDbSearchPage {
        let config = await connection()
        let payload = try await client.decode(WirePage.self, path: type == .movie ? "/search/movie" : "/search/tv",
            query: [URLQueryItem(name: "query", value: query), URLQueryItem(name: "language", value: language),
                    URLQueryItem(name: "page", value: String(page))], connection: config)
        try Task.checkCancellation()
        return TMDbSearchPage(results: payload.results.map {
            TMDbSearchResult(source: MediaSource(mediaType: type, remoteID: $0.id, language: language, fetchedAt: Date()),
                title: $0.title ?? $0.name ?? $0.original_title ?? $0.original_name ?? "",
                date: $0.release_date ?? $0.first_air_date, overview: $0.overview, posterPath: $0.poster_path)
        }, page: payload.page, totalPages: payload.total_pages)
    }
    private func path(_ source: MediaSource) -> String {
        switch source.mediaType {
        case .movie: "/movie/\(source.remoteID)"
        case .series: "/tv/\(source.remoteID)"
        case .season: "/tv/\(source.parentSeriesID ?? 0)/season/\(source.seasonNumber ?? 0)"
        }
    }
    private func record(_ source: MediaSource, config: TMDbConnection) async throws -> TMDbRecord {
        let key = "\(config.generation):\(source.identity):\(source.language)"
        if let (value, date) = records[key], Date().timeIntervalSince(date) < 300 { return value }
        let client = self.client; let endpoint = path(source)
        let value = try await recordTasks.value(for: key) {
            try await client.decode(TMDbRecord.self, path: endpoint,
                query: [URLQueryItem(name: "language", value: source.language)], connection: config)
        }
        try Task.checkCancellation()
        records[key] = (value, Date())
        if records.count > 50 { records = [key: (value, Date())] }
        return value
    }
    func details(_ source: MediaSource) async throws -> TMDbImportDraft {
        let config = await connection()
        let endpoint = path(source)
        let language = [URLQueryItem(name: "language", value: source.language)]
        async let raw = record(source, config: config)
        async let images = optional(WireImages.self, path: endpoint + "/images", query: [], config: config)
        async let credits = optional(WireCredits.self, path: endpoint + "/credits", query: language, config: config)
        let parentSource = MediaSource(mediaType: .series, remoteID: source.parentSeriesID ?? source.remoteID,
                                      language: source.language, fetchedAt: source.fetchedAt)
        async let parent = source.mediaType == .season ? record(parentSource, config: config) : nil
        let (r, imageSet, creditSet, parentRecord) = try await (raw, images, credits, parent)
        try Task.checkCancellation()
        let base = parentRecord ?? r
        let localized = base.title ?? base.name ?? base.original_title ?? base.original_name ?? ""
        let seasonName = source.mediaType == .season ? r.name : nil
        let title = seasonName.map { "\(localized) · \($0)" } ?? localized
        let candidates = sortedImages(imageSet?.posters ?? [], language: source.language, original: base.original_language).map(\.file_path)
        var logoSet = imageSet?.logos ?? []
        var background = r.backdrop_path ?? base.backdrop_path
        if source.mediaType == .season {
            let parentImages = await optional(WireImages.self, path: path(parentSource) + "/images", query: [], config: config)
            logoSet = parentImages?.logos ?? []
            background = background ?? parentImages?.backdrops?.first?.file_path
        }
        let logo = sortedImages(logoSet, language: source.language, original: base.original_language).first?.file_path
        let metadata = MediaMetadata(localizedTitle: localized, originalTitle: base.original_title ?? base.original_name,
            seasonTitle: seasonName, overview: r.overview, releaseDate: r.release_date ?? r.first_air_date ?? r.air_date,
            genres: base.genres?.map(\.name) ?? [], remoteStatus: base.status,
            runtimeMinutes: r.runtime ?? base.episode_run_time?.first, episodeCount: r.number_of_episodes ?? r.episodes?.count,
            tmdbRating: r.vote_average, homepage: base.homepage,
            posterPath: candidates.first ?? r.poster_path ?? base.poster_path,
            backdropPath: background ?? imageSet?.backdrops?.first?.file_path, logoPath: logo,
            companies: base.production_companies?.map { MediaCompany(id: $0.id, name: $0.name, logoPath: $0.logo_path) } ?? [],
            cast: creditSet?.cast?.prefix(20).map(\.local) ?? [], crew: creditSet?.crew?.prefix(20).map(\.local) ?? [],
            seasons: r.seasons?.map(\.local) ?? [], episodes: r.episodes?.map(\.local) ?? [])
        var updatedSource = source; updatedSource.fetchedAt = Date()
        var warnings: [String] = []
        if imageSet == nil { warnings.append(String(localized: "图片目录获取失败，使用基本资料中的图片。")) }
        if creditSet == nil { warnings.append(String(localized: "演职员获取失败，可以继续导入。")) }
        return TMDbImportDraft(source: updatedSource, title: title, metadata: metadata,
                              posterCandidates: candidates.isEmpty ? [metadata.posterPath].compactMap { $0 } : candidates,
                              warnings: warnings)
    }
    private func optional<T: Decodable & Sendable>(_ type: T.Type, path: String, query: [URLQueryItem], config: TMDbConnection) async -> T? {
        try? await client.decode(type, path: path, query: query, connection: config)
    }
    private func sortedImages(_ images: [WireImages.Resource], language: String, original: String?) -> [WireImages.Resource] {
        let preferred = String(language.prefix(2))
        func priority(_ image: WireImages.Resource) -> Int {
            if image.iso_639_1 == preferred { return 0 }
            if image.iso_639_1 == original { return 1 }
            if image.iso_639_1 == nil { return 2 }
            return 3
        }
        return images.sorted { priority($0) == priority($1) ? ($0.vote_average ?? 0) > ($1.vote_average ?? 0) : priority($0) < priority($1) }
    }
    private func imageConfig(_ config: TMDbConnection) async -> ImageConfiguration {
        if let (value, date) = configurations[config.generation], Date().timeIntervalSince(date) < 86400 { return value }
        let old = configurations[config.generation]?.0 ?? .fallback
        let client = self.client
        do {
            let value = try await configTasks.value(for: config.generation.uuidString) {
                try await client.decode(ImageConfiguration.self, path: "/configuration", connection: config)
            }
            try Task.checkCancellation()
            configurations[config.generation] = (value, Date())
            if configurations.count > 4 { configurations = [config.generation: (value, Date())] }
            return value
        } catch { return old }
    }
    func imageURL(_ path: String, role: String, width: Int) async -> URL? {
        let config = await imageConfig(await connection())
        return resolvedImageURL(path, role: role, width: width, configuration: config)
    }
    /// Read-only details must never send an authenticated configuration request.
    func cachedImageURL(_ path: String, role: String, width: Int) async -> URL? {
        let config = await connection()
        return resolvedImageURL(path, role: role, width: width, configuration: configurations[config.generation]?.0 ?? .fallback)
    }
    private func resolvedImageURL(_ path: String, role: String, width: Int, configuration: ImageConfiguration) -> URL? {
        let config = configuration.images
        let sizes: [String]
        switch role {
        case "backdrop": sizes = config.backdrop_sizes
        case "logo": sizes = config.logo_sizes
        case "profile": sizes = config.profile_sizes
        case "still": sizes = config.still_sizes
        default: sizes = config.poster_sizes
        }
        let size = sizes.compactMap { size -> (String, Int)? in
            guard size.hasPrefix("w"), let number = Int(size.dropFirst()) else { return nil }
            return (size, number)
        }.sorted { $0.1 < $1.1 }.first { $0.1 >= width }?.0 ?? "original"
        let safePath = path.replacingOccurrences(of: ".svg", with: ".png")
        guard safePath.hasPrefix("/"), !safePath.contains(".."), !safePath.contains(":") else { return nil }
        let url = URL(string: config.secure_base_url + size + safePath)
        return url?.scheme == "https" ? url : nil
    }
}
