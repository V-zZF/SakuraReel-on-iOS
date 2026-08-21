import SwiftUI

struct MediaCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterView(imageData: item.poster)
                .aspectRatio(Constants.posterAspectRatio, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    PlayButtonOverlay(playURL: item.playURL)
                }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                RatingLabel(rating: item.rating)

                Spacer()

                if let year = item.watchYear, let month = item.watchMonth {
                    Text(String(format: "%04d.%02d", year, month))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))
        .shadow(color: .black.opacity(0.06), radius: Constants.cardShadowRadius, x: 0, y: 2)
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
