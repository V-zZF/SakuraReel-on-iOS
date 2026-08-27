import SwiftUI
import PhotosUI

/// 海报选择器：PhotosPicker + 2:3 缩略图。
///
/// 绑定已压缩的海报数据（由 `PosterResizer` 处理），
/// 用户从相册选中图片后立即裁剪压缩并写入绑定。
struct PosterImagePicker: View {
    @Binding var posterData: Data?

    @State private var selectedPhotoItem: PhotosPickerItem?

    private var posterImage: UIImage? {
        posterData.flatMap { UIImage(data: $0) }
    }

    var body: some View {
        HStack(spacing: 16) {
            if let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 85)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 85)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(posterData == nil ? "暂无海报" : "已选择海报")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(posterData == nil ? "添加海报" : "更换海报", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Constants.accentPink)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                guard let rawData = try? await newItem?.loadTransferable(type: Data.self),
                      let image = UIImage(data: rawData) else { return }
                posterData = PosterResizer.resizedPosterData(from: image)
            }
        }
    }
}
