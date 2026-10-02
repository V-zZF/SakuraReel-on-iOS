//
//  MediaMetadata.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import Foundation

enum TMDbMediaType: String, Codable, CaseIterable, Sendable {
    case movie, series, season
}

enum TMDbIdentity: Codable, Hashable, Sendable {
    case movie(id: Int)
    case series(id: Int)
    case season(id: Int, seriesID: Int, number: Int)
    var mediaType: TMDbMediaType { switch self { case .movie: .movie; case .series: .series; case .season: .season } }
    var remoteID: Int { switch self { case .movie(let id), .series(let id), .season(let id, _, _): id } }
    var parentSeriesID: Int? { if case .season(_, let id, _) = self { id } else { nil } }
    var seasonNumber: Int? { if case .season(_, _, let number) = self { number } else { nil } }
    var key: String {
        switch self {
        case .movie(let id): "tmdb:movie:\(id)"
        case .series(let id): "tmdb:series:\(id)"
        case .season(let id, let parent, let number): "tmdb:season:\(parent):\(number):\(id)"
        }
    }
}
struct MediaSource: Codable, Hashable, Sendable {
    var tmdb: TMDbIdentity
    var language: String
    var fetchedAt: Date
    var mediaType: TMDbMediaType { tmdb.mediaType }
    var remoteID: Int { tmdb.remoteID }
    var parentSeriesID: Int? { tmdb.parentSeriesID }
    var seasonNumber: Int? { tmdb.seasonNumber }
    var identity: String { tmdb.key }
    init(tmdb: TMDbIdentity, language: String, fetchedAt: Date) {
        self.tmdb = tmdb; self.language = language; self.fetchedAt = fetchedAt
    }
    var webpage: URL? {
        let path: String
        switch tmdb {
        case .movie(let id): path = "movie/\(id)"
        case .series(let id): path = "tv/\(id)"
        case .season(_, let parent, let number): path = "tv/\(parent)/season/\(number)"
        }
        return URL(string: "https://www.themoviedb.org/\(path)")
    }
}

struct MediaCredit: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var role: String
    var imagePath: String?
}
struct MediaCompany: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var name: String
    var logoPath: String?
}
struct MediaPart: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var number: Int
    var title: String
    var overview: String?
    var date: String?
    var episodeCount: Int?
    var imagePath: String?
}
struct MediaMetadata: Codable, Hashable, Sendable {
    var originalTitle: String?
    var seasonTitle: String?
    var overview: String?
    var releaseDate: String?
    var genres: [String] = []
    var remoteStatus: String?
    var runtimeMinutes: Int?
    var episodeCount: Int?
    var tmdbRating: Double?
    var homepage: String?
    var posterPath: String?
    var backdropPath: String?
    var logoPath: String?
    var companies: [MediaCompany] = []
    var cast: [MediaCredit] = []
    var crew: [MediaCredit] = []
    var seasons: [MediaPart] = []
    var episodes: [MediaPart] = []
    /// TV runtime is an average per episode, so the total is explicitly an estimate.
    func totalRuntimeMinutes(for type: TMDbMediaType?) -> (minutes: Int, isEstimated: Bool)? {
        guard let runtime = runtimeMinutes, runtime > 0 else { return nil }
        let isTV = type == .series || type == .season || (type == nil && episodeCount != nil)
        guard isTV else { return (runtime, false) }
        guard let count = episodeCount, count > 0 else { return nil }
        let total = runtime.multipliedReportingOverflow(by: count)
        guard !total.overflow else { return nil }
        return (total.partialValue, true)
    }

    var statusLabel: String? {
        guard let remoteStatus else { return nil }
        switch remoteStatus {
        case "Released": return String(localized: "已上映")
        case "Returning Series": return String(localized: "连载中")
        case "Ended": return String(localized: "已完结")
        case "Canceled": return String(localized: "已取消")
        case "In Production": return String(localized: "制作中")
        case "Post Production": return String(localized: "后期制作")
        case "Planned": return String(localized: "计划中")
        case "Pilot": return String(localized: "试播")
        case "Rumored": return String(localized: "传闻")
        default: return remoteStatus
        }
    }

}

/// A fetched draft has no repository side effects. Personal fields never occur here.
struct TMDbImportDraft: Sendable {
    var source: MediaSource
    var title: String
    var metadata: MediaMetadata
    var poster: Data?
    var backdrop: Data?
    var logo: Data?
    var posterCandidates: [String] = []
    var warnings: [String] = []
}

enum MetadataField: String, CaseIterable, Identifiable, Sendable {
    case title, originalTitle, seasonTitle, overview, releaseDate, genres, remoteStatus
    case runtimeMinutes, episodeCount, tmdbRating, homepage, companies, cast, crew, seasons, episodes
    case poster, backdrop, logo
    var id: String { rawValue }
    var label: String {
        switch self {
        case .title: String(localized: "片名")
        case .originalTitle: String(localized: "原名")
        case .seasonTitle: String(localized: "季度名")
        case .overview: String(localized: "简介")
        case .releaseDate: String(localized: "上映／首播日期")
        case .genres: String(localized: "影视类型")
        case .remoteStatus: String(localized: "作品状态")
        case .runtimeMinutes: String(localized: "时长（分钟）")
        case .episodeCount: String(localized: "集数")
        case .tmdbRating: String(localized: "TMDb 评分")
        case .homepage: String(localized: "官网")
        case .companies: String(localized: "制作公司")
        case .cast: String(localized: "演员")
        case .crew: String(localized: "职员")
        case .seasons: String(localized: "季度")
        case .episodes: String(localized: "单集")
        case .poster: String(localized: "海报")
        case .backdrop: String(localized: "背景图")
        case .logo: "Logo"
        }
    }
    func value(in item: MediaItem) -> String {
        let m = item.metadata ?? MediaMetadata()
        switch self {
        case .title: return item.title
        case .originalTitle: return m.originalTitle ?? ""
        case .seasonTitle: return m.seasonTitle ?? ""
        case .overview: return m.overview ?? ""
        case .releaseDate: return m.releaseDate ?? ""
        case .genres: return m.genres.joined(separator: "、")
        case .remoteStatus: return m.remoteStatus ?? ""
        case .runtimeMinutes: return m.runtimeMinutes.map(String.init) ?? ""
        case .episodeCount: return m.episodeCount.map(String.init) ?? ""
        case .tmdbRating: return m.tmdbRating.map { String($0) } ?? ""
        case .homepage: return m.homepage ?? ""
        case .companies: return m.companies.map(\.name).joined(separator: "、")
        case .cast: return m.cast.map { "\($0.name) · \($0.role)" }.joined(separator: "、")
        case .crew: return m.crew.map { "\($0.name) · \($0.role)" }.joined(separator: "、")
        case .seasons: return m.seasons.map(\.title).joined(separator: "、")
        case .episodes: return m.episodes.map(\.title).joined(separator: "、")
        case .poster: return item.attachments.poster == nil ? "" : String(localized: "已保存图片")
        case .backdrop: return item.attachments.backdrop == nil ? "" : String(localized: "已保存图片")
        case .logo: return item.attachments.logo == nil ? "" : String(localized: "已保存图片")
        }
    }
}

extension TMDbImportDraft {
    var previewItem: MediaItem {
        MediaItem(title: title, poster: poster, status: .watched, source: source,
                  metadata: metadata, backdrop: backdrop, logo: logo)
    }
    func defaults(for item: MediaItem) -> Set<MetadataField> {
        Set(MetadataField.allCases.filter { $0.value(in: item).isEmpty && !$0.value(in: previewItem).isEmpty })
    }
    func merging(into item: MediaItem, fields: Set<MetadataField>) -> MediaItem {
        var result = item
        var m = item.metadata ?? MediaMetadata()
        for field in fields {
            switch field {
            case .title: result.title = title
            case .originalTitle: m.originalTitle = metadata.originalTitle
            case .seasonTitle: m.seasonTitle = metadata.seasonTitle
            case .overview: m.overview = metadata.overview
            case .releaseDate: m.releaseDate = metadata.releaseDate
            case .genres: m.genres = metadata.genres
            case .remoteStatus: m.remoteStatus = metadata.remoteStatus
            case .runtimeMinutes: m.runtimeMinutes = metadata.runtimeMinutes
            case .episodeCount: m.episodeCount = metadata.episodeCount
            case .tmdbRating: m.tmdbRating = metadata.tmdbRating
            case .homepage: m.homepage = metadata.homepage
            case .companies: m.companies = metadata.companies
            case .cast: m.cast = metadata.cast
            case .crew: m.crew = metadata.crew
            case .seasons: m.seasons = metadata.seasons
            case .episodes: m.episodes = metadata.episodes
            case .poster: if let poster { result.poster = poster; m.posterPath = metadata.posterPath }
            case .backdrop: if let backdrop { result.backdrop = backdrop; m.backdropPath = metadata.backdropPath }
            case .logo: if let logo { result.logo = logo; m.logoPath = metadata.logoPath }
            }
        }
        result.source = source
        result.metadata = m
        return result
    }
}
