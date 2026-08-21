import SwiftUI

struct PosterPlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
            .fill(Constants.accentPink.opacity(0.15))
            .aspectRatio(Constants.posterAspectRatio, contentMode: .fit)
            .overlay {
                Image(systemName: "film.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Constants.accentPink.opacity(0.6))
            }
    }
}

#Preview {
    PosterPlaceholderView()
        .frame(width: 160)
        .padding()
}
