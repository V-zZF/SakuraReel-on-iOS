import SwiftUI

/// 观看年月选择：年 + 月两个独立 Picker。
///
/// 年可选项含「未设置」（nil），未设置时隐藏月份选择；
/// 选定年后若月份为空则默认当前月，切回「未设置」时月份同步清空。
struct YearMonthPickers: View {
    @Binding var year: Int?
    @Binding var month: Int?

    private var yearRange: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return (1970...currentYear).reversed()
    }

    var body: some View {
        Picker(selection: $year) {
            Text("未设置").tag(Int?.none)
            ForEach(yearRange, id: \.self) { y in
                Text("\(y) 年").tag(Int?.some(y))
            }
        } label: {
            Label("观看年", systemImage: "calendar")
        }
        .onChange(of: year) { _, newYear in
            if newYear == nil {
                month = nil
            } else if month == nil {
                month = Calendar.current.component(.month, from: Date())
            }
        }

        if year != nil {
            Picker(selection: $month) {
                ForEach(1...12, id: \.self) { m in
                    Text("\(m) 月").tag(Int?.some(m))
                }
            } label: {
                Label("观看月", systemImage: "calendar")
            }
        }
    }
}
