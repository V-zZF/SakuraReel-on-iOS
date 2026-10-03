import SwiftUI

struct EmptyStateView: View {
    let status: MediaStatus?
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "film.stack")
        } description: {
            Text(description)
        } actions: {
            LibraryAddCapsule(title: "添加作品", action: action)
        }
    }

    private var title: String {
        status == nil ? "无搜索结果" : "还没有作品"
    }

    private var description: String {
        switch status {
        case .watched: return "看过列表还是空的，先添加一部吧。"
        case .watching: return "没有正在看的作品，开始追一部新剧。"
        case .wantToWatch: return "想看列表是空的，把想看的作品记下来。"
        default: return "试试其他关键词，或添加一部新作品。"
        }
    }
}

/// Shared capsule appearance for library and manual-add entry points.
struct LibraryAddCapsule: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .sakuraGlassBackground(shape: Capsule())
                .clipShape(Capsule())
        }
        .buttonStyle(LibraryPressStyle())
    }
}

#Preview("空状态") {
    EmptyStateView(status: .watched) {}
}
