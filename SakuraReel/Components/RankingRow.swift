import SwiftUI

/// 排行榜的横向列表条目：排名 + 海报 + 片名 + 观看年月 + 评分。
///
/// 纯展示，不含点击 / 拖动逻辑 —— 两种模式分别由 `RankingsView` 挂手势。
/// 行内没有按钮，因此不需要 `MediaCard` 那样的 `isInteractive` 开关来避让拖动。
///
/// 卡片尺寸不由这里决定：`cardHeight` 由 `RankingMetrics` 按「一屏几张」算出，
/// 卡内每个尺寸都写成「基准值 × scale」，所以整张卡片连同内容一起等比缩放。
struct RankingRow: View {
    /// 列表内序号，从 1 开始
    let rank: Int
    let item: MediaItem
    /// 卡片高度，来自 `RankingMetrics.cardHeight`
    let cardHeight: CGFloat

    /// 相对基准卡高的放大倍数。下方所有 pt 数值的基准值都对应 scale == 1 的现状尺寸
    private var scale: CGFloat { cardHeight / RankingMetrics.baseCardHeight }

    var body: some View {
        HStack(spacing: 0) {
            // 海报铺满卡片左侧、高度即卡片高度（宽度按 2:3 反推），
            // 圆角由外层 clipShape 统一裁剪（与 MediaCard 同一做法）
            PosterView(imageData: item.poster, cornerRadius: 0)
                .frame(width: cardHeight * Constants.posterAspectRatio)
                .clipped()

            VStack(alignment: .leading, spacing: 6 * scale) {
                HStack(spacing: 4 * scale) {
                    Text("#")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.secondary)
                    Text("\(rank)")
                        .font(.system(size: 15 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                    // 卡片变大后一行放不下几个字，允许换到第二行 —— 行高由海报决定，不会因此变高
                    Text(item.title)
                        .font(.system(size: 15 * scale, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                HStack(spacing: 4 * scale) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11 * scale))
                    Text(watchDateText)
                        .font(.system(size: 12 * scale))
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12 * scale)

            Spacer(minLength: 8 * scale)

            RatingLabel(rating: item.rating, size: 22 * scale, captionSize: 12 * scale)
                .padding(.trailing, 14 * scale)
        }
        .modifier(LibraryCardSurface(scale: scale))
    }

    /// 观看年月。未设置时保留日历图标，文字以「未设置」占位，保证行内元素位置固定。
    private var watchDateText: String {
        guard let year = item.watchYear, let month = item.watchMonth else { return "未设置" }
        return String(format: "%04d-%02d", year, month)
    }
}

#Preview("基准尺寸") {
    VStack(spacing: RankingMetrics.baseGap) {
        RankingRow(rank: 1, item: PreviewSampleData.sampleItems[0],
                   cardHeight: RankingMetrics.baseCardHeight)
        RankingRow(rank: 2, item: PreviewSampleData.sampleItems[3],
                   cardHeight: RankingMetrics.baseCardHeight)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("无海报") {
    VStack(spacing: RankingMetrics.baseGap) {
        RankingRow(rank: 5, item: PreviewSampleData.sampleItems[1],
                   cardHeight: RankingMetrics.baseCardHeight)
        RankingRow(rank: 6, item: PreviewSampleData.sampleItems[4],
                   cardHeight: RankingMetrics.baseCardHeight)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("iPhone 一屏五张") {
    let metrics = RankingMetrics(availableSize: CGSize(width: 393, height: 718), isPad: false)
    return VStack(spacing: metrics.gap) {
        ForEach(Array(PreviewSampleData.sampleItems.prefix(5).enumerated()), id: \.element.id) { index, item in
            RankingRow(rank: index + 1, item: item, cardHeight: metrics.cardHeight)
        }
    }
    .padding(metrics.listPadding)
    .frame(width: metrics.listWidth)
    .background(Color(.systemGroupedBackground))
}
