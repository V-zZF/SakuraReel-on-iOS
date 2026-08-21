import SwiftUI
import UIKit

/// 首页导航栏分类选择器：SwiftUI Segmented Picker + 独立搜索按钮
///
/// 遵循系统 UISegmentedControl（.segmented）的呈现与交互（含原生滑动切换），
/// 选中文字为主题粉加粗，未选中浅灰；搜索按钮独立放在选择器右侧。
struct CategorySegmentedControl: View {
    @Binding var selectedStatus: MediaStatus?
    @Binding var isSearchActive: Bool

    private let statuses = MediaStatus.allCases

    init(selectedStatus: Binding<MediaStatus?>, isSearchActive: Binding<Bool>) {
        self._selectedStatus = selectedStatus
        self._isSearchActive = isSearchActive

        // 文字外观：选中樱花粉加粗 / 未选中浅灰
        UISegmentedControl.appearance().setTitleTextAttributes(
            [
                .foregroundColor: UIColor(Constants.accentPink),
                .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            ],
            for: .selected
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor.lightGray],
            for: .normal
        )
    }

    var body: some View {
        HStack(spacing: 16) {
            Picker("", selection: $selectedStatus) {
                ForEach(statuses, id: \.id) { status in
                    // 尾部空格占位，撑大滑块、拉开段间距
                    Text(status.displayName + "     ")
                        .tag(Optional(status))
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .onChange(of: selectedStatus) { _, _ in
                // 点击分类时退出搜索
                isSearchActive = false
            }

            Button {
                isSearchActive = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Constants.accentPink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索")
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var selectedStatus: MediaStatus? = .watched
        @State var isSearchActive: Bool = false

        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    Text("SakuraReel")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.accentPink)
                        .padding(.top, 8)

                    CategorySegmentedControl(selectedStatus: $selectedStatus, isSearchActive: $isSearchActive)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    Spacer()
                }
            }
        }
    }

    return PreviewWrapper()
}
