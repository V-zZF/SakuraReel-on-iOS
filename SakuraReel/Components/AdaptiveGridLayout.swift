import SwiftUI

/// 网格容器的可用宽度（含两侧留白）从内容区回传，供宽度感知的列数使用。
///
/// `defaultValue` 必须是 `static let`：Swift 6 下 `static var` 是可变全局状态，编译不过。
struct GridWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AdaptiveGridLayout<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// 网格容器的可用宽度（含两侧留白）。`0` = 还没量到，退回尺寸类的答案
    var availableWidth: CGFloat = 0

    @ViewBuilder let content: () -> Content

    /// 列数唯一来源：尺寸类给上限（紧凑竖屏 3 列、Regular 5 列、其余 2 列），
    /// 再由 `GridColumns` 按可用宽度收窄 —— 算术本身在 `GridColumns` 里，可脱离模拟器验证。
    /// 正常模式网格与排序模式网格共用，保证两套布局永不漂移。
    static func columnCount(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?,
        availableWidth: CGFloat = 0
    ) -> Int {
        let maxColumns: Int
        if verticalSizeClass == .compact {
            maxColumns = 3
        } else if horizontalSizeClass == .regular {
            maxColumns = 5
        } else {
            maxColumns = 2
        }
        return GridColumns.count(
            maxColumns: maxColumns,
            availableWidth: availableWidth,
            spacing: GridColumns.spacing
        )
    }

    private var columnCount: Int {
        Self.columnCount(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            availableWidth: availableWidth
        )
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Constants.gridSpacing), count: columnCount),
            spacing: Constants.gridSpacing
        ) {
            content()
        }
        .padding(Constants.gridSpacing)
        // 首页网格跟随系统动态字体，但封顶：再大下去，评分行会先被挤爆 ——
        // 那行里的评分数值与播放按钮都是不跟随的显式字号，只有日期会涨。
        // 只封网格不封全局：`.sheet` 会继承呈现者的环境，封在 NavigationStack 上会把
        // 添加 / 编辑表单一起封掉，而表单恰恰是最需要大字号的地方。
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

#Preview {
    AdaptiveGridLayout {
        ForEach(0..<6, id: \.self) { index in
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    Text("\(index + 1)")
                        .font(.title.bold())
                        .foregroundStyle(.secondary)
                }
        }
    }
}
