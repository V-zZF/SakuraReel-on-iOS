import SwiftUI

struct PosterView: View {
    let imageData: Data?
    var cornerRadius: CGFloat = Constants.cardCornerRadius

    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                // Color.clear 撑满整个 2:3 区域，图片 scaledToFill 填满并裁剪溢出
                Color.clear
                    .overlay {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
            } else {
                PosterPlaceholderView()
            }
        }
        .aspectRatio(Constants.posterAspectRatio, contentMode: .fit)
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
