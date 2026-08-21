import SwiftUI

struct AdaptiveGridLayout<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ViewBuilder let content: () -> Content

    private var columnCount: Int {
        if verticalSizeClass == .compact {
            return 3
        }
        if horizontalSizeClass == .regular {
            return 5
        }
        return 2
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
