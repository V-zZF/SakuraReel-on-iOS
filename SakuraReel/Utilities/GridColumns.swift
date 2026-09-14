import CoreGraphics

/// 首页网格列数的唯一来源。
///
/// 列数先由尺寸类给出**上限**（紧凑竖屏 3 / Regular 5 / 其余 2），再按容器**可用宽度**收窄 ——
/// 卡片窄于 `minCardWidth` 就少排一列。这一条只在 iPad 分栏（Split View / Slide Over）这类
/// 「尺寸类仍是 regular、实际却很窄」的场合生效：整屏 iPhone 与整屏 iPad 算出来的结果与尺寸类
/// 的答案一致，行为与从前逐帧相同。
///
/// 只依赖 CoreGraphics（**不 import SwiftUI**），与 `RankingMetrics` 同构 ——
/// 列数算术要能脱离模拟器验证。这条约束要保持。
enum GridColumns {
    /// 列间距，同时也是网格两侧的留白（`AdaptiveGridLayout` 两者同值）。
    /// 这里是唯一来源：`Constants.gridSpacing` 直接引用它 —— 本文件不 import SwiftUI，
    /// 所以列数算术能在模型层测试里脱离模拟器验证，间距也得跟着能读到。
    static let spacing: CGFloat = 16

    /// 卡片最小可读宽度。低于它宁可少排一列。
    static let minCardWidth: CGFloat = 110

    /// - Parameters:
    ///   - maxColumns: 尺寸类给出的上限
    ///   - availableWidth: 网格容器的可用宽度（**含**两侧留白）；`0` = 还没量到
    ///   - spacing: 列间距，同时也是网格两侧的留白（`AdaptiveGridLayout` 两者同值）
    ///   - minCardWidth: 卡片最小宽度，默认 `minCardWidth`
    static func count(
        maxColumns: Int,
        availableWidth: CGFloat,
        spacing: CGFloat,
        minCardWidth: CGFloat = minCardWidth
    ) -> Int {
        // 宽度还没量到：原样返回尺寸类的答案。首帧因此与从前逐帧相同，不会先按窄布局画一帧再跳
        guard availableWidth > 0 else { return maxColumns }

        let usable = availableWidth - 2 * spacing
        guard usable > 0 else { return 1 }

        // n 列放得下 ⟺ n × minCardWidth + (n − 1) × spacing ≤ usable
        let fit = Int((usable + spacing) / (minCardWidth + spacing))
        return max(1, min(maxColumns, fit))
    }
}
