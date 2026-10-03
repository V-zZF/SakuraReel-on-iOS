import CoreGraphics

/// 按当前内容区像素宽度计算列数，不依赖设备、方向或尺寸类。
enum GridColumns {
    static let spacing: CGFloat = 16

    /// 每张卡片与分摊到它的周围间隙合计占宽，以屏幕像素计。
    // iPad Pro 11寸横屏参考宽2388px，均分五个卡片占位。
    // 这里只定义尺寸基准，实际列数仍由当前窗口宽度计算。
    static let cardSlotPixels: CGFloat = 2388.0 / 5

    static func count(availableWidth: CGFloat, displayScale: CGFloat) -> Int {
        guard availableWidth.isFinite, availableWidth > 0,
              displayScale.isFinite, displayScale > 0 else { return 1 }
        // 消除像素与pt换算在精确列数门槛上的浮点误差。
        let fit = (availableWidth * displayScale / cardSlotPixels + 1e-9).rounded(.down)
        guard fit > 1 else { return 1 }
        return Int(min(fit, CGFloat(Int.max / 2)))
    }
}
