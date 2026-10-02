import Foundation

func runTimeMachineMomentsTests() {
    print("\n— 时光机季度与封面 —")

    func item(_ title: String, month: Int?, rating: Int = 0,
              status: MediaStatus = .watched, rankIndex: Int? = nil) -> MediaItem {
        MediaItem(title: title, status: status, watchYear: 2024,
                  watchMonth: month, rating: rating, sortIndex: 0, rankIndex: rankIndex)
    }

    let source = [
        item("三月", month: 3, rating: 7),
        item("四月", month: 4, rating: 8),
        item("六月", month: 6),
        item("七月", month: 7),
        item("九月", month: 9),
        item("十月", month: 10),
        item("十二月", month: 12),
        item("无月份", month: nil),
        item("无效月份", month: 13),
        item("在看", month: 3, status: .watching),
        item("想看", month: 3, status: .wantToWatch),
    ]
    let moments = TimeMachineMoments.moments(from: source)
    expectEqual(moments.map(\.quarter.number), [4, 3, 2, 1], "季度按新到旧")
    expectEqual(moments.map(\.count), [2, 2, 2, 1], "仅计入看过且年月完整的作品")
    expectEqual(moments.map(\.quarter.season), ["秋", "夏", "春", "冬"], "自然季度的季节标签")
    expectEqual(moments.map(\.quarter.monthRange), ["10–12 月", "7–9 月", "4–6 月", "1–3 月"], "月份边界")
    expectEqual(moments[1].rankedItems.map(\.title), ["九月", "七月"], "未评分作品也参与季度，并按观看月份排序")
    var yearless = item("无年份", month: 3)
    yearless.watchYear = nil
    expect(TimeMachineMoments.quarter(for: yearless) == nil, "缺失观看年份不进入季度")

    let tie = TimeMachineMoments.moments(from: [
        item("第二名", month: 2, rating: 10, rankIndex: 1),
        item("第一名", month: 1, rating: 10, rankIndex: 0),
        item("低分", month: 3, rating: 8),
    ])
    expectEqual(tie[0].representative.title, "第一名", "同分代表封面沿用排行榜名次")
    expectEqual(tie[0].rankedItems.map(\.title), ["第一名", "第二名", "低分"], "季度作品使用排行榜顺序")

    var older = item("旧年", month: 12, rating: 10)
    older.watchYear = 2023
    var newer = item("新年", month: 1, rating: 0)
    newer.watchYear = 2025
    expectEqual(TimeMachineMoments.moments(from: [older, newer]).map(\.quarter.year),
                [2025, 2023], "季度顺序先比较年份")

    let noPoster = item("最高分但无海报", month: 1, rating: 10)
    let withPoster = item("次高分", month: 2, rating: 9)
    expectEqual(TimeMachineMoments.moments(from: [noPoster, withPoster])[0].representative.id,
                noPoster.id, "代表封面优先按评分选择，不跳过无海报作品")

    expectEqual(TimeMachineMoments.centerOut([Int]()), [], "空列表")
    expectEqual(TimeMachineMoments.centerOut([1]), [1], "单张卡片")
    expectEqual(TimeMachineMoments.centerOut([1, 2]), [2, 1], "两张卡片")
    expectEqual(TimeMachineMoments.centerOut([1, 2, 3, 4, 5, 6, 7]), [6, 4, 2, 1, 3, 5, 7], "奇数张从中心展开")
    expectEqual(TimeMachineMoments.centerOut([1, 2, 3, 4, 5, 6]), [6, 4, 2, 1, 3, 5], "偶数张从中心展开")
    expect(TimeMachineMoments.moments(from: []).isEmpty, "空库没有季度")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
    func quarter(_ year: Int, _ number: Int) -> TimeMachineMoments.Quarter {
        .init(year: year, number: number)
    }
    func moment(_ year: Int, _ month: Int) -> TimeMachineMoments.Moment {
        var media = item("季度", month: month)
        media.watchYear = year
        return TimeMachineMoments.moments(from: [media])[0]
    }
    let available = [moment(2026, 7), moment(2025, 7), moment(2024, 10)]
    expectEqual(TimeMachineMoments.openingQuarter(in: available, today: today, calendar: calendar),
                quarter(2025, 3), "进入时默认选中去年的当前季度")
    expectEqual(TimeMachineMoments.openingQuarter(in: [available[0], available[2]], today: today, calendar: calendar),
                quarter(2024, 4), "目标季度为空时先找更早的季度")
    expectEqual(TimeMachineMoments.openingQuarter(in: [available[0]], today: today, calendar: calendar),
                quarter(2026, 3), "只有更新季度时选择最近的一个")
    expect(TimeMachineMoments.openingQuarter(in: [], today: today, calendar: calendar) == nil,
           "空库没有默认季度")
}
