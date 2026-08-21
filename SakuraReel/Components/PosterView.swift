import SwiftUI

struct PosterView: View {
    let imageData: Data?
    var cornerRadius: CGFloat = Constants.cardCornerRadius

    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                PosterPlaceholderView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

#Preview("有海报") {
    PosterView(imageData: PreviewSampleData.sampleItems[0].poster)
        .frame(width: 160)
        .padding()
}

#Preview("无海报") {
    PosterView(imageData: nil)
        .frame(width: 160)
        .padding()
}
