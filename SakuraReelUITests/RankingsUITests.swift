import XCTest

/// Phase 5 排行榜的 UI 验证。
///
/// 运行前需要库里存在这样一组数据（由 Scripts/run-ui-tests.sh 写入模拟器容器）：
/// - 评分 10：攻壳机动队（2024-05）/ 千年女优（2024-05）/ 千与千寻（2024-03）
///   —— 同评分不同观看年月，正是「复用 sortIndex 会静默失效」的场景
/// - 评分 9：星际穿越（2024-03） / 评分 8：你想活出怎样的人生（2024-03）
/// - 评分 7：沙丘2（2024-01） / 未评分：阿诺拉（未设年月）
///
/// 默认榜单顺序（未手动排过时）：攻壳机动队 → 千年女优 → 千与千寻 → 星际穿越
/// → 你想活出怎样的人生 → 沙丘2 → 阿诺拉。
///
/// 这些断言会真实拖动条目，是真机/模拟器上的端到端验证，不是逻辑单测。
final class RankingsUITests: XCTestCase {

    private var app: XCUIApplication!

    /// 全部榜单条目标题，按默认名次排列
    private let defaultOrder = [
        "攻壳机动队", "千年女优", "千与千寻", "星际穿越",
        "你想活出怎样的人生", "沙丘2", "阿诺拉",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["千与千寻"].waitForExistence(timeout: 10),
                      "首页没加载出测试数据，请先写入 Documents/SakuraReelLibrary.json")
        openRankings()
    }

    // MARK: - 工具

    /// 从首页工具栏的「排行」Push 进入排行榜
    private func openRankings() {
        let button = app.buttons["排行"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "找不到「排行」按钮")
        button.tap()
        XCTAssertTrue(app.navigationBars["评分排行榜"].waitForExistence(timeout: 5),
                      "没进入排行榜")
    }

    private func row(_ title: String) -> XCUIElement {
        app.staticTexts[title]
    }

    private func enterSortMode() {
        let button = app.buttons["排序"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "找不到「排序」按钮")
        button.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5), "没进入排序模式")
    }

    /// 排行榜是单列，只比纵坐标即可
    private func isBefore(_ a: String, _ b: String) -> Bool {
        row(a).frame.minY < row(b).frame.minY
    }

    private func assertOrder(_ titles: [String], _ stage: String) {
        for (i, earlier) in titles.enumerated() {
            for later in titles[(i + 1)...] {
                XCTAssertTrue(isBefore(earlier, later),
                              "[\(stage)] 期望「\(earlier)」在「\(later)」之前，实际榜单：\(snapshot())")
            }
        }
    }

    /// 失败时把当前榜单顺序打进日志，便于定位
    private func snapshot() -> String {
        defaultOrder
            .filter { row($0).exists }
            .sorted { isBefore($0, $1) }
            .joined(separator: " / ")
    }

    private func drag(_ from: String, onto to: String) {
        let source = row(from)
        let target = row(to)
        XCTAssertTrue(source.exists, "找不到条目「\(from)」")
        XCTAssertTrue(target.exists, "找不到条目「\(to)」")
        source.press(forDuration: 1.2, thenDragTo: target)
    }

    // MARK: - 1. 榜单顺序与第二行摘要

    func testRankingOrderAndSummary() {
        assertOrder(defaultOrder, "初始")

        let summary = app.descendants(matching: .any)
            .matching(identifier: "rankingSummary")
            .firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "找不到「共 N 部 / 平均 N 分」摘要行")
        // 7 部全部收录；平均只算已评分的 6 部：(10+10+10+9+8+7)/6 = 9.0
        XCTAssertEqual(summary.label, "共 7 部 平均 9.0 分", "摘要行数值不符")
    }

    // MARK: - 2. 未评分条目排最后，行内显示占位

    func testUnratedItemIsLastWithPlaceholders() {
        // 只断言「未评分排在已评分之后」这一条，不依赖完整顺序 ——
        // 本用例按字母序排在提交用例之后，全量顺序那时已经被改过了
        // 阿诺拉未评分且未设年月：评分位「未评」，日期行「未设置」
        XCTAssertTrue(app.staticTexts["未评"].exists, "未评分条目应显示「未评」")
        XCTAssertTrue(app.staticTexts["未设置"].exists, "未设观看年月应显示「未设置」")
        XCTAssertTrue(isBefore("沙丘2", "阿诺拉"), "未评分条目应排在所有已评分条目之后")
    }

    // MARK: - 3. 同评分内拖动重排 → 完成后落盘并跨启动保持

    /// 关键用例：拖动跨越了**不同的观看年月**（千与千寻 2024-03 → 攻壳机动队 2024-05）。
    /// 若手动顺序复用 sortIndex，这一步会被观看时间规则静默覆盖；rankIndex 才能让它生效。
    func testReorderWithinRatingThenCommitPersists() {
        assertOrder(defaultOrder, "初始")
        enterSortMode()

        drag("千与千寻", onto: "攻壳机动队")
        XCTAssertTrue(isBefore("千与千寻", "攻壳机动队"),
                      "拖动后草稿顺序应已改变，实际：\(snapshot())")

        app.buttons["完成"].tap()

        let expected = ["千与千寻", "攻壳机动队", "千年女优", "星际穿越",
                        "你想活出怎样的人生", "沙丘2", "阿诺拉"]
        assertOrder(expected, "提交后")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["千与千寻"].waitForExistence(timeout: 10))
        openRankings()
        assertOrder(expected, "重启后")
    }

    // MARK: - 4. 跨评分拖动被阻止并弹提示

    func testCrossRatingDragIsBlocked() {
        enterSortMode()
        assertOrder(defaultOrder, "初始")

        // 评分 9 的星际穿越拖到评分 10 的千与千寻上
        drag("星际穿越", onto: "千与千寻")

        let alert = app.alerts["无法移动"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "跨评分拖动应弹出提示")
        XCTAssertTrue(alert.staticTexts["只能调整相同评分内的作品顺序。"].exists,
                      "提示文案不符")
        alert.buttons["好"].tap()

        assertOrder(defaultOrder, "阻止后")
    }

    // MARK: - 5. ✕ 放弃草稿并回滚

    func testCancelRollsBackReorder() {
        assertOrder(defaultOrder, "初始")
        enterSortMode()

        drag("千与千寻", onto: "攻壳机动队")
        XCTAssertTrue(isBefore("千与千寻", "攻壳机动队"),
                      "拖动后草稿顺序应已改变，实际：\(snapshot())")

        // 排序模式下返回按钮被 ✕ 取代，导航栏左侧第一个按钮即 ✕
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertOrder(defaultOrder, "取消后")
    }

    // MARK: - 6. 点条目打开编辑 Sheet；排序模式下不响应

    func testTapRowOpensEditSheet() {
        row("攻壳机动队").tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 5),
                      "普通模式下点条目应打开编辑 Sheet")
        app.buttons["取消"].tap()

        enterSortMode()
        row("攻壳机动队").tap()
        XCTAssertFalse(app.buttons["保存"].waitForExistence(timeout: 2),
                       "排序模式下点条目不应打开编辑 Sheet")
        XCTAssertTrue(app.buttons["完成"].exists, "不应因点击条目而退出排序模式")
    }
}
