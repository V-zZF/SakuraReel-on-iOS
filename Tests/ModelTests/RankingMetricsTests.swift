import CoreGraphics
import Foundation

// 排行榜卡片尺寸规则的断言。
// 由 main.swift 调用，断言计数与失败汇总也在那边。

private func expectClose(_ actual: CGFloat, _ expected: CGFloat, _ label: String,
                         tolerance: CGFloat = 0.001) {
    expect(abs(actual - expected) <= tolerance, "\(label)：期望 \(expected)，实际 \(actual)")
}

/// 「一屏正好 N 张」成立的形态：iPhone（竖横都算）与 iPad 横屏
private let fivePerScreenCases: [(size: CGSize, isPad: Bool)] = [
    (CGSize(width: 393, height: 718), false),    // iPhone 17 Pro 竖屏
    (CGSize(width: 852, height: 393), false),    // iPhone 17 Pro 横屏
    (CGSize(width: 1210, height: 720), true),    // iPad Pro 11" 横屏
    (CGSize(width: 1024, height: 768), true),    // iPad 横屏（旧机型尺寸）
]

/// iPad 竖屏：不按「一屏几张」走，改用宽度做高度预算
private let padPortraitCases: [(size: CGSize, isPad: Bool)] = [
    (CGSize(width: 834, height: 1100), true),    // iPad Pro 11" 竖屏
    (CGSize(width: 1032, height: 1262), true),   // iPad Pro 13" 竖屏
]

/// 卡片长宽比（卡宽 ÷ 卡高）。竖屏与横屏应基本一致 —— 「卡高和横屏同一档」的判定依据
private func cardAspect(_ metrics: RankingMetrics) -> CGFloat {
    (metrics.listWidth - 2 * metrics.listPadding) / metrics.cardHeight
}

func runRankingMetricsTests() {
    print("\n— 排行榜卡片尺寸 —")

    // 1. 核心承诺：一屏正好放得下 5 张 —— 5 张卡 + 4 个间距 + 上下留白 == 可用高度
    for testCase in fivePerScreenCases {
        let metrics = RankingMetrics(availableSize: testCase.size, isPad: testCase.isPad)
        let filled = RankingMetrics.cardsPerScreen * metrics.cardHeight
            + (RankingMetrics.cardsPerScreen - 1) * metrics.gap
            + 2 * metrics.listPadding
        expectClose(filled, testCase.size.height,
                    "iPad=\(testCase.isPad) \(testCase.size) 时 5 张卡应正好铺满")
        expectClose(metrics.cardHeight,
                    testCase.size.height / RankingMetrics.heightBudgetSlots,
                    "iPad=\(testCase.isPad) \(testCase.size) 的卡高应由可用高度摊分")
    }

    // 2. iPad 竖屏：改用**宽度**摊分，与可用高度无关 —— 屏再高也不会把卡片撑大
    for testCase in padPortraitCases {
        let metrics = RankingMetrics(availableSize: testCase.size, isPad: true)
        expectClose(metrics.cardHeight,
                    testCase.size.width / RankingMetrics.heightBudgetSlots,
                    "iPad 竖屏 \(testCase.size) 的卡高应由可用宽度摊分")
        expectClose(metrics.listWidth, testCase.size.width, "iPad 竖屏整列应铺满屏幕宽")
    }

    // 3. 「卡高和横屏同一档」：两种朝向的卡片长宽比应基本一致
    let padPortrait = RankingMetrics(availableSize: CGSize(width: 834, height: 1100), isPad: true)
    let padLandscape = RankingMetrics(availableSize: CGSize(width: 1210, height: 720), isPad: true)
    expectClose(cardAspect(padPortrait), cardAspect(padLandscape),
                "iPad 竖屏与横屏的卡片长宽比应一致", tolerance: 0.2)
    // 竖屏若仍按可用高度摊，卡高会是 1100/5.8 ≈ 190 —— 现在是 144 上下，明显更矮
    expect(padPortrait.cardHeight < 1100 / RankingMetrics.heightBudgetSlots * 0.9,
           "iPad 竖屏不该按可用高度摊（实际 \(padPortrait.cardHeight)）")

    // 4. 基准：可用高度 = 基准卡高 × 份数 时，卡高必须正好回到基准 90 ——
    //    也就是说 scale == 1 仍然是这次改动前的现状尺寸
    let baseline = RankingMetrics(availableSize: CGSize(width: 393, height: 90 * 5.8), isPad: false)
    expectClose(baseline.cardHeight, RankingMetrics.baseCardHeight, "基准可用高度下卡高应为 90")
    expectClose(baseline.scale, 1, "基准可用高度下放大倍数应为 1")
    expectClose(baseline.gap, RankingMetrics.baseGap, "基准可用高度下间距应为 12")
    expectClose(baseline.listPadding, RankingMetrics.basePadding, "基准可用高度下留白应为 12")

    // 5. 等比：卡高翻倍，卡内间距与留白跟着翻倍，而不是留在原值
    let doubled = RankingMetrics(availableSize: CGSize(width: 393, height: 90 * 5.8 * 2), isPad: false)
    expectClose(doubled.cardHeight, 180, "可用高度翻倍后卡高应翻倍")
    expectClose(doubled.scale, 2, "可用高度翻倍后放大倍数应为 2")
    expectClose(doubled.gap, 24, "间距应跟着卡高一起放大")
    expectClose(doubled.listPadding, 24, "留白应跟着卡高一起放大")

    // 6. 宽度：iPhone 与 iPad 竖屏铺满整屏；iPad 横屏收成一列 ——
    //    卡片比「半屏宽一列」的卡片宽 1/5，且整列仍窄于屏幕（否则没地方居中）
    expectClose(RankingMetrics(availableSize: CGSize(width: 393, height: 718), isPad: false).listWidth,
                393, "iPhone 整列应铺满屏幕宽")

    let padCardWidth = padLandscape.listWidth - 2 * padLandscape.listPadding
    let halfScreenCardWidth = 1210 / 2 - 2 * padLandscape.listPadding
    expectClose(padCardWidth, halfScreenCardWidth * RankingMetrics.padCardWidthMultiplier,
                "iPad 横屏卡片应比半屏宽一列的卡片宽 1/5")
    expect(padLandscape.listWidth < 1210, "iPad 横屏整列仍须窄于屏幕，否则没地方居中")

    // 注意：卡高变大 → 留白跟着变大 → 在「半屏宽」这个固定预算里卡片反而略窄。
    // 这是留白与卡高同比缩放的必然结果，不是 bug，所以不为它写断言

    // 7. 可用高度退化成 0（首帧、被收起的容器）也不能算出 0 或负的卡高 —— 负尺寸会让布局报错
    let degenerate = RankingMetrics(availableSize: CGSize(width: 0, height: 0), isPad: false)
    expect(degenerate.cardHeight > 0, "可用高度为 0 时卡高仍须为正数，实际 \(degenerate.cardHeight)")

    // 8. iPad 分栏（Split View 2/3，约 556pt 宽）下卡高由**宽度**摊分 —— 那是「竖屏用宽度做预算」
    //    这条既定规则的自然结果。加个「窄栏当作 iPhone」的门槛试过，已回退：
    //    门槛两侧卡高会从 172pt 跳到 103pt，拖动分栏分隔线经过门槛时卡片会瞬间跳一下，
    //    而分栏本来就只在 2/3 档才是 regular 宽度，不会窄到撑不住
    let splitNarrow = RankingMetrics(availableSize: CGSize(width: 556, height: 1100), isPad: true)
    expectClose(splitNarrow.cardHeight, 556 / RankingMetrics.heightBudgetSlots,
                "iPad 分栏（regular 宽度）卡高仍应由宽度摊分")
    expect(splitNarrow.cardHeight >= RankingMetrics.baseCardHeight,
           "分栏下卡高不该比基准卡高还小，实际 \(splitNarrow.cardHeight)")
}
