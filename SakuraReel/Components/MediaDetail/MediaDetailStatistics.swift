// Layout adapted from AniShelf, Copyright 2024 Samuel He (Apache-2.0).
// Modified for SakuraReel on 2026-10-02. See Resources/ThirdPartyNotices.txt.
import SwiftUI

/// The first row belongs to the user's library record, not remote ratings.
struct MediaDetailStatistics: View {
    let item: MediaItem
    let onEditPersonalRecord: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 8) { grid }
            } else { grid }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            Button(action: onEditPersonalRecord) {
                card("我的评分", value: item.rating == 0 ? "未评分" : "\(item.rating)", symbol: "star.fill")
                    .contentShape(Rectangle())
            }.buttonStyle(LibraryPressStyle()).accessibilityHint("编辑个人记录")
            Button(action: onEditPersonalRecord) {
                card("观看年月", value: item.personal.watchedAt.map { "\($0.year)年\($0.month)月" } ?? "未设置", symbol: "calendar")
                    .contentShape(Rectangle())
            }.buttonStyle(LibraryPressStyle()).accessibilityHint("编辑个人记录")
            card("总时长", value: item.metadata?.totalRuntimeMinutes(for: item.source?.mediaType).map {
                "\($0.isEstimated ? "约" : "")\($0.minutes) 分钟"
            } ?? "未设置", symbol: "clock.fill")
        }
    }

    private func card(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading) {
            Image(systemName: symbol).font(.headline).foregroundStyle(Constants.brandTitlePink)
            Spacer()
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.55)
            Spacer()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 85, maxHeight: 85, alignment: .topLeading)
        .padding(16).modifier(MediaDetailPanel())
        .accessibilityElement(children: .combine)
    }
}

/// Remote metadata is collected beneath the personal cards and review.
struct MediaDetailWorkStatistics: View {
    let metadata: MediaMetadata
    let type: TMDbMediaType?
    let onEpisodes: (() -> Void)?

    private var hasContent: Bool {
        metadata.tmdbRating != nil || metadata.episodeCount != nil || metadata.runtimeMinutes != nil || !metadata.companies.isEmpty
    }

    var body: some View {
        if hasContent {
            MediaDetailSection(title: "作品资料", symbol: "info.circle") {
                VStack(alignment: .leading, spacing: 14) {
                    if let rating = metadata.tmdbRating {
                        LabeledContent("TMDb 评分", value: String(format: "%.1f", rating))
                    }
                    if type != .movie, let count = metadata.episodeCount {
                        if let onEpisodes {
                            Button(action: onEpisodes) {
                                HStack {
                                    Text("集数").foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(count) 集").foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Constants.brandTitlePink)
                                }
                            }.buttonStyle(LibraryPressStyle()).accessibilityHint("跳转到单集")
                        } else { LabeledContent("集数", value: "\(count) 集") }
                    }
                    if let runtime = metadata.runtimeMinutes {
                        LabeledContent(type == .movie ? "时长" : "平均单集时长", value: "\(runtime) 分钟")
                    }
                    if !metadata.companies.isEmpty {
                        LabeledContent("制作公司") {
                            Text(metadata.companies.map(\.name).joined(separator: "、"))
                                .multilineTextAlignment(.trailing).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}
