import SwiftUI

struct RatingLabel: View {
    let rating: Int

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            if rating > 0 {
                Text("\(rating)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(RatingColor.color(for: rating))
                Text("分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("未评")
                    .font(.caption)
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
