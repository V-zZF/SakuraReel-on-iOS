import CoreGraphics

/// 排行榜卡片尺寸的唯一来源。
///
/// 卡片大小不写死成 pt，而是量化成「**一屏放几张**」：卡片高度由高度预算摊分得出，
/// 卡内所有元素（海报、文字、图标、评分、圆角、阴影）再按卡片高度等比缩放。
/// 于是只要改 `cardsPerScreen` 一个数，整页卡片连同内容一起变大变小。
///
/// 高度预算按屏幕形态分两种：
/// - **iPhone（竖横都算）与 iPad 横屏**：用列表可用高度，即一屏正好 `cardsPerScreen` 张
/// - **iPad 竖屏**：改用列表可用**宽度** —— 竖屏屏太高，按可用高度摊会把卡片撑成巨无霸；
///   而竖屏的宽度就是横屏时的屏高，于是竖屏卡高与横屏同一档（只差一个导航栏 + 摘要行）
///
/// 只依赖 CoreGraphics（**不 import SwiftUI**），所以能被 `Scripts/run-model-tests.sh`
/// 单独编译跑断言 —— 「一屏正好放得下 N 张」这条得能脱离模拟器验证。这条约束要保持。
struct RankingMetrics {
    /// 一屏放几张卡片
    static let cardsPerScreen: CGFloat = 5

    /// 基准卡高（pt）。卡内字号、间距、圆角、阴影都按「卡高 ÷ 这个数」等比缩放。
    /// 90 = 海报宽 60 × 3/2，也就是放大倍数为 1 时排行榜卡片的现状尺寸。
    static let baseCardHeight: CGFloat = 90

    /// 卡片间距、列表四周留白的基准值（同基准卡高，一起等比缩放）
    static let baseGap: CGFloat = 12
    static let basePadding: CGFloat = 12

    /// iPad **横屏**下卡片相对「半屏宽一列」的加宽倍数：铺满整屏会把卡片拉成一条长带，
    /// 半屏宽的一列又偏窄，取半屏宽的卡片再宽 1/5。竖屏不受它影响（竖屏铺满宽度）
    static let padCardWidthMultiplier: CGFloat = 1.2

    /// 高度预算 ÷ 这个份数 = 卡高。
    /// 份数 = N 张卡 + (N-1) 个间距 + 上下留白，后两者按卡高折算成同一单位
    static var heightBudgetSlots: CGFloat {
        let gapRatio = baseGap / baseCardHeight
        let paddingRatio = basePadding / baseCardHeight
        return cardsPerScreen + (cardsPerScreen - 1) * gapRatio + 2 * paddingRatio
    }

    /// 卡片高度：由高度预算摊分得出（预算取可用高度还是可用宽度见 `init`）
    let cardHeight: CGFloat
    /// 列表实际可见高度，用于仅让进场时可见的行参与动画。
    let availableHeight: CGFloat
    /// 整列（卡片 + 左右留白）的总宽度
    let listWidth: CGFloat

    /// - Parameters:
    ///   - availableSize: 列表可用区域，由调用方用 GeometryReader 量出
    ///   - isPad: iPad 横屏整列收窄居中；iPad 竖屏铺满宽度并改用「横屏那一档」卡高
    init(availableSize: CGSize, isPad: Bool) {
        // iPad 竖屏：改用宽度做高度预算。竖屏的宽度就是横屏时的屏高，所以竖屏卡高与横屏
        // 同一档（差一个导航栏 + 摘要行的量），也不会在很高的屏上被撑成巨无霸。
        // 代价是竖屏不再「一屏正好 N 张」—— 一屏能放多少放多少。
        let isPadPortrait = isPad && availableSize.height > availableSize.width
        let heightBudget = isPadPortrait ? availableSize.width : availableSize.height
        let height = max(heightBudget, 1) / Self.heightBudgetSlots
        cardHeight = height
        availableHeight = availableSize.height

        // 固定宽度、只在计算中途用一次，所以就地算而不是读计算属性
        // （初始化没走完之前不能碰 self）
        let padding = Self.basePadding * Self.scale(forCardHeight: height)

        // iPhone 与 iPad 竖屏铺满可用宽度；iPad 横屏按「半屏宽一列的卡片再宽 1/5」定列宽
        // （整列由调用方居中）—— 加宽算在卡片上而不是整列上，所以先减掉左右留白、乘完再加回来
        if isPad && !isPadPortrait {
            let halfScreenCardWidth = availableSize.width / 2 - 2 * padding
            listWidth = halfScreenCardWidth * Self.padCardWidthMultiplier + 2 * padding
        } else {
            listWidth = availableSize.width
        }
    }

    /// 卡内尺寸相对基准的放大倍数，`RankingRow` 里的每个 pt 数值都是「基准值 × scale」
    var scale: CGFloat { Self.scale(forCardHeight: cardHeight) }

    /// 卡片间距
    var gap: CGFloat { Self.baseGap * scale }

    /// 列表四周留白
    var listPadding: CGFloat { Self.basePadding * scale }

    private static func scale(forCardHeight height: CGFloat) -> CGFloat {
        height / baseCardHeight
    }
}
