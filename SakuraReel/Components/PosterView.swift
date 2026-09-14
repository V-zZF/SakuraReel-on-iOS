import SwiftUI

struct PosterView: View {
    let imageData: Data?
    var cornerRadius: CGFloat = Constants.cardCornerRadius

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // 淡入挂在「数据从无到有」这一刻，**不能**挂 `.onAppear`：海报是同步解码的，
        // 卡片一重建就已经有 Data，而 `LazyVGrid` 回收单元格时会丢掉 `@State` ——
        // 挂 onAppear 的话，滚回来的卡片会先空一帧再淡入，那就是闪烁。
        // 动画值用 Bool 而不是 Data：`Data` 的 `==` 是比较整个 JPEG
        .animation(
            reduceMotion ? nil : .easeOut(duration: Constants.posterFadeInDuration),
            value: imageData == nil
        )
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
