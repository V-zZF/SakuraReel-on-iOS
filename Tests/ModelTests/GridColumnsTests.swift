import CoreGraphics
import Foundation

// 首页网格列数的断言。
// 由 main.swift 调用，断言计数与失败汇总也在那边。
//
// 这些用例是「iPad 分栏该排几列」唯一能脱离模拟器证明的地方 ——
// 分栏宽度没法在 UI 测试里复现，只能把算术抽出来单测。

private let spacing = GridColumns.spacing

/// 尺寸类给出的上限：紧凑竖屏 3 / Regular 5 / 其余 2
private let compactLandscape = 3
private let regular = 5
private let phonePortrait = 2

func runGridColumnsTests() {
    print("\n— 首页网格列数 —")

    // 1. 整屏 iPhone 与整屏 iPad：算出来必须与尺寸类的答案一致，
    //    否则「iPad 分栏适配」就顺手改掉了整屏的既定布局
    let unchanged: [(width: CGFloat, max: Int, expected: Int, note: String)] = [
        (402, phonePortrait, 2, "iPhone 17 Pro 竖屏"),
        (393, phonePortrait, 2, "iPhone 17 Pro 竖屏（旧值）"),
        (375, phonePortrait, 2, "iPhone SE / 13 mini"),
        (852, compactLandscape, 3, "iPhone 17 Pro 横屏"),
        (834, regular, 5, "iPad Pro 11\" 竖屏"),
        (1210, regular, 5, "iPad Pro 11\" 横屏"),
        (1024, regular, 5, "iPad 旧机型横屏"),
    ]
    for c in unchanged {
        expectEqual(
            GridColumns.count(maxColumns: c.max, availableWidth: c.width, spacing: spacing),
            c.expected,
            "\(c.note)（宽 \(c.width)）应仍是 \(c.expected) 列"
        )
    }

    // 2. 分栏变窄 → 自动减列。这正是本轮加规则的目的
    let narrowed: [(width: CGFloat, expected: Int, note: String)] = [
        (807, 5, "iPad 横屏 2/3 分栏"),
        (646, 5, "刚好还放得下 5 列"),
        (645, 4, "比 5 列的门槛少 1pt"),
        (556, 4, "iPad 竖屏 2/3 分栏"),
        (507, 3, "iPad 横屏 1/2 分栏"),
        (320, 2, "Slide Over / 1/3 分栏"),
        (200, 1, "极窄：至少留 1 列"),
    ]
    for c in narrowed {
        expectEqual(
            GridColumns.count(maxColumns: regular, availableWidth: c.width, spacing: spacing),
            c.expected,
            "\(c.note)（宽 \(c.width)）应排 \(c.expected) 列"
        )
    }

    // 3. 分列的门槛算术：n 列放得下 ⟺ n×minCardWidth + (n−1)×spacing ≤ usable
    //    宽度 646 → usable 614 → 5×110 + 4×16 = 614，正好放下，不该减列
    let minCardWidth = GridColumns.minCardWidth
    expectClose(5 * minCardWidth + 4 * spacing, 646 - 2 * spacing,
                "宽 646 应正好是 5 列的门槛")
    expect(5 * minCardWidth + 4 * spacing > 645 - 2 * spacing,
           "宽 645 应差 1pt 够不到 5 列")
    expect(4 * minCardWidth + 3 * spacing <= 645 - 2 * spacing,
           "宽 645 仍应放得下 4 列")

    // 4. 量不到宽度时退回尺寸类的答案 —— 首帧就是今天的样子，不会先按窄布局画一帧再跳
    for maxColumns in [2, 3, 5] {
        expectEqual(
            GridColumns.count(maxColumns: maxColumns, availableWidth: 0, spacing: spacing),
            maxColumns,
            "宽度未知时应原样返回尺寸类的答案（\(maxColumns) 列）"
        )
    }

    // 5. 退化输入不出负数、不崩
    expectEqual(GridColumns.count(maxColumns: regular, availableWidth: 1, spacing: spacing),
                1, "宽度比两侧留白还小时至少 1 列")
    // 负宽度当作「没量到」而不是「极窄」：真按极窄处理会排成 1 列，
    // 某个瞬间量出负值的话整页会闪一下单列，退回尺寸类的答案才稳
    expectEqual(GridColumns.count(maxColumns: regular, availableWidth: -100, spacing: spacing),
                5, "负宽度时退回尺寸类的答案")
    expectEqual(GridColumns.count(maxColumns: regular, availableWidth: 646, spacing: 0),
                5, "留白为 0 时按上限走")
}

/// 与 `RankingMetricsTests` 里同名函数各写各的：两边都只是本文件内部的小工具，
/// 提到共享文件反而把两个互不相关的断言集绑在一起
private func expectClose(_ actual: CGFloat, _ expected: CGFloat, _ label: String,
                         tolerance: CGFloat = 0.001) {
    expect(abs(actual - expected) <= tolerance, "\(label)：期望 \(expected)，实际 \(actual)")
}
