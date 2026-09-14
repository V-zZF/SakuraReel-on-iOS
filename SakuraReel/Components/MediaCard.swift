import SwiftUI

struct MediaCard: View {
    let item: MediaItem

    /// 卡片内部交互（评分弹短评、播放入口）是否响应触摸。
    /// 排序模式下设为 false，避免与拖动重排的手势抢触摸。
    var isInteractive: Bool = true
    var onOpen: (() -> Void)?

    @State private var showReviewAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 海报 + 片名同属一个动作（打开编辑），合并成**一个** Button：
            // 整块只有一次按压态、一个无障碍元素 —— 此前拆成两个 Button 时 VoiceOver
            // 会对同一动作连读两遍（「编辑千与千寻」/「千与千寻」）
            //
            // 无障碍标签显式写成片名：合成标签会把子元素拼在一起，显式写才稳定；
            // 同时给一个同名 identifier，「片名」由此成为卡片在测试里唯一的定位点
            Button { onOpen?() } label: {
                VStack(alignment: .leading, spacing: 0) {
                    // 海报铺满卡片顶部，无左右上边距；PosterView 内部自带 2:3 约束与 fill 裁剪
                    PosterView(imageData: item.poster, cornerRadius: 0)
                        .clipped()

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // 原先文字区是一个 VStack(spacing: 8).padding(12)，
                        // 拆开写要逐项对上：片名上方 12、左右 12、与评分行之间 8
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }
            }
            .buttonStyle(LibraryPressStyle())
            // 显式写标签：合成标签会把海报与片名拼在一起，显式写才稳定，
            // `app.buttons["片名"]` 也因此能唯一定位到这张卡片
            .accessibilityLabel(item.title)
            .accessibilityHint("编辑")
            .allowsHitTesting(isInteractive && onOpen != nil)

            // 评分 + 日期 + 播放按钮同一行：评分靠左，日期与播放按钮靠右。
            // 这三者留在上面那个 Button **外面**，各自仍是独立的可点区域
            HStack(alignment: .center, spacing: 8) {
                // 评分区域可点击：弹出短评
                Button {
                    showReviewAlert = true
                } label: {
                    RatingLabel(rating: item.rating)
                }
                .buttonStyle(LibraryPressStyle())
                .sensoryFeedback(.selection, trigger: showReviewAlert) { _, shown in shown }

                Spacer()

                if let year = item.watchYear, let month = item.watchMonth {
                    Text(String(format: "%04d.%02d", year, month))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // 放大字号时这一行最先被挤到截断：宁可缩小也不截断
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                PlayButtonOverlay(playURL: item.playURL)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .allowsHitTesting(isInteractive)
        }
        .modifier(LibraryCardSurface())
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
