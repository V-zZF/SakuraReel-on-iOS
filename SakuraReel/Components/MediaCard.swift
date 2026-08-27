import SwiftUI

struct MediaCard: View {
    let item: MediaItem

    @State private var showReviewAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 海报：铺满卡片顶部，无左右上边距；比例不适配时填充裁剪而非缩小留白
            // PosterView 内部自带 2:3 约束与 fill 裁剪，此处不需要再套 aspectRatio
            PosterView(imageData: item.poster, cornerRadius: 0)
                .clipped()

            // 文字区：海报下方白底区域
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                // 评分 + 日期 + 播放按钮同一行：评分靠左，日期与播放按钮靠右
                HStack(alignment: .center, spacing: 8) {
                    // 评分区域可点击：弹出短评
                    Button {
                        showReviewAlert = true
                    } label: {
                        RatingLabel(rating: item.rating)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if let year = item.watchYear, let month = item.watchMonth {
                        Text(String(format: "%04d.%02d", year, month))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    PlayButtonOverlay(playURL: item.playURL)
                }
            }
            .padding(12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))
        .shadow(color: .black.opacity(0.06), radius: Constants.cardShadowRadius, x: 0, y: 2)
        .alert("\(item.title)  短评", isPresented: $showReviewAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(reviewText)
        }
    }

    private var reviewText: String {
        let review = item.review?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return review.isEmpty ? "暂无短评" : review
    }
}

#Preview("有海报") {
    MediaCard(item: PreviewSampleData.sampleItems[0])
        .frame(width: 160)
        .padding()
}

#Preview("无海报") {
    MediaCard(item: PreviewSampleData.sampleItems[3])
        .frame(width: 160)
        .padding()
}
