import SwiftUI

struct AdaptiveGridLayout<Content: View>: View {
    @Environment(\.displayScale) private var displayScale
    /// 当前内容区宽度（含两侧留白），由呈现页面持续测量。
    var availableWidth: CGFloat = 0

    @ViewBuilder let content: () -> Content

    private var columnCount: Int {
        GridColumns.count(availableWidth: availableWidth, displayScale: displayScale)
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
