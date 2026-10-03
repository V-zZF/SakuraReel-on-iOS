import CoreGraphics
import Foundation

func runGridColumnsTests() {
    print("\n— iPad Pro 11寸横屏五张参考自适应网格 —")
    let cases: [(CGFloat, CGFloat, Int)] = [
        (393, 3, 2), (852, 3, 5),
        (834, 2, 3), (1024, 2, 4), (1194, 2, 5), (1210, 2, 5), (1366, 2, 5),
        (320, 2, 1), (556, 2, 2), (1650, 2, 6),
        (1100, 1, 2)
    ]
    for (width, scale, columns) in cases {
        expectEqual(GridColumns.count(availableWidth: width, displayScale: scale), columns,
                    "窗口宽\(width)pt、\(scale)x应排\(columns)列")
    }
    for scale in [CGFloat(1), 2, 3] {
        for columns in 2...8 {
            let threshold = CGFloat(columns) * GridColumns.cardSlotPixels / scale
            expectEqual(GridColumns.count(availableWidth: threshold, displayScale: scale), columns,
                        "卡片占宽门槛包含等号")
            expectEqual(GridColumns.count(availableWidth: threshold - 1, displayScale: scale), columns - 1,
                        "门槛前1pt减列")
        }
    }
    // 窗口缩放与旋转往返，以及窗口移到不同显示比例的屏幕。
    for (width, scale, columns) in cases.reversed() {
        expectEqual(GridColumns.count(availableWidth: width, displayScale: scale), columns,
                    "往返调整不保留旧列数")
    }
    for width in [CGFloat(0), -100, 1, .infinity, .nan] {
        expectEqual(GridColumns.count(availableWidth: width, displayScale: 2), 1, "非法或极窄宽度至少一列")
    }
    for scale in [CGFloat(0), -1, .infinity, .nan] {
        expectEqual(GridColumns.count(availableWidth: 1024, displayScale: scale), 1, "非法显示比例安全回退")
    }
}
