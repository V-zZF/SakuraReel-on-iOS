import SwiftUI

struct AdaptiveGridLayout<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ViewBuilder let content: () -> Content

    /// 列数唯一来源：紧凑竖屏 3 列、Regular 横屏 5 列、其余 2 列。
    /// 正常模式网格与排序模式网格共用，保证两套布局永不漂移。
    static func columnCount(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> Int {
        if verticalSizeClass == .compact {
            return 3
        }
        if horizontalSizeClass == .regular {
            return 5
        }
        return 2
    }

    private var columnCount: Int {
        Self.columnCount(horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Constants.gridSpacing), count: columnCount),
            spacing: Constants.gridSpacing
        ) {
            content()
        }
        .padding(Constants.gridSpacing)
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
