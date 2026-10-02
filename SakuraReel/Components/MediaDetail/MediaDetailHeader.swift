// Layout adapted from AniShelf, Copyright 2024 Samuel He (Apache-2.0).
// Modified for SakuraReel on 2026-10-02. See Resources/ThirdPartyNotices.txt.
import SwiftUI

struct MediaDetailHeader: View {
    let item: MediaItem
    static let coordinateSpace = "mediaDetailScroll"
    private let height: CGFloat = 420

    private var metadataLine: String {
        let metadata = item.metadata
        let date = metadata?.releaseDate.map(Self.formattedDate)
        return [date, metadata?.episodeCount.map { "\($0) 集" }, metadata?.statusLabel]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }

    private static func formattedDate(_ value: String) -> String {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return value }
        return "\(parts[0])年\(parts[1])月\(parts[2])日"
    }

    var body: some View {
        GeometryReader { proxy in
            let overscroll = max(proxy.frame(in: .named(Self.coordinateSpace)).minY, 0)
            artwork(width: proxy.size.width, height: height + overscroll)
                .offset(y: -overscroll)
        }.frame(height: height)
    }

    private func artwork(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let data = item.backdrop ?? item.poster, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: width, height: height)
                    .accessibilityHidden(true)
            } else {
                Color(.systemGray5)
                    .overlay { Image(systemName: "film").font(.system(size: 52)).foregroundStyle(.white.opacity(0.55)) }
            }
            LinearGradient(colors: [.black.opacity(0.42), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22))
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: UnitPoint(x: 0.5, y: 0.35), endPoint: .bottom)
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, Constants.libraryBackground], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
            }
            VStack(spacing: 6) {
                if let data = item.logo, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 280).frame(height: 78)
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 6).accessibilityLabel(item.title)
                } else {
                    Text(item.title).font(.largeTitle.bold()).foregroundStyle(.white)
                        .lineLimit(3).minimumScaleFactor(0.78).multilineTextAlignment(.center)
                }
                if let season = item.metadata?.seasonTitle, !season.isEmpty {
                    Text(season).font(.subheadline).foregroundStyle(.white.opacity(0.82)).lineLimit(2)
                }
                if !metadataLine.isEmpty {
                    Text(metadataLine).font(.footnote).foregroundStyle(.white.opacity(0.68)).lineLimit(2)
                }
                if let genres = item.metadata?.genres, !genres.isEmpty {
                    Text(genres.joined(separator: ", ")).font(.caption).foregroundStyle(.white.opacity(0.56)).lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360).padding(.horizontal, 24).padding(.bottom, 36).frame(maxWidth: .infinity)
        }.frame(width: width, height: height).clipped()
    }
}
