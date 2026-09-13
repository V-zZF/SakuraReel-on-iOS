import SwiftUI

struct RatingLabel: View {
    let rating: Int

    /// 评分数值字号。首页卡片用默认 30pt；排行榜行按卡片高度算。
    var size: CGFloat = 30

    /// 「分」/「未评」后缀的字号。nil（默认）= 用系统 `.caption`，即首页现状；
    /// 排行榜整行等比放大时传算好的字号，后缀连同间距一起放大。
    var captionSize: CGFloat? = nil

    /// 后缀相对 12pt 基准的倍数，只用来同比放大数值与后缀之间的间距
    private var captionScale: CGFloat { (captionSize ?? 12) / 12 }

    private var captionFont: Font {
        guard let captionSize else { return .caption }
        return .system(size: captionSize)
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2 * captionScale) {
            if rating > 0 {
                Text("\(rating)")
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(RatingColor.color(for: rating))
                Text("分")
                    .font(captionFont)
                    .foregroundStyle(.secondary)
            } else {
                Text("未评")
                    .font(captionFont)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("已评分") {
    RatingLabel(rating: 10)
        .padding()
}

#Preview("未评分") {
    RatingLabel(rating: 0)
        .padding()
}
