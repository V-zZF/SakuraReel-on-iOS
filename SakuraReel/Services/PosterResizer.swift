import UIKit

/// 海报图片处理：居中裁剪为 2:3、缩放到 ≤900px 高、压缩为 JPEG 0.85。
///
/// 用 `UIGraphicsImageRenderer` + aspect-fill 绘制（自动处理图片 orientation），
/// `format.scale = 1` 保证输出像素尺寸精确，控制海报文件体积。
enum PosterResizer {
    nonisolated static func resizedPosterData(from image: UIImage, maxHeight: CGFloat = 900) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let targetAspect: CGFloat = 2.0 / 3.0
        let targetWidth = maxHeight * targetAspect
        let targetSize = CGSize(width: targetWidth, height: maxHeight)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        let resized = renderer.image { _ in
            // aspect-fill：保持原比例居中铺满 2:3 画布，超出部分自然裁掉
            let imageSize = image.size
            let imageAspect = imageSize.width / imageSize.height

            var drawRect = CGRect(origin: .zero, size: targetSize)
            if imageAspect > targetAspect {
                // 图片更宽：按高度铺满，裁剪左右
                let drawWidth = targetSize.height * imageAspect
                drawRect.origin.x = (targetSize.width - drawWidth) / 2
                drawRect.size.width = drawWidth
            } else {
                // 图片更高：按宽度铺满，裁剪上下
                let drawHeight = targetWidth / imageAspect
                drawRect.origin.y = (targetSize.height - drawHeight) / 2
                drawRect.size.height = drawHeight
            }
            image.draw(in: drawRect)
        }

        return resized.jpegData(compressionQuality: 0.85)
    }
}
