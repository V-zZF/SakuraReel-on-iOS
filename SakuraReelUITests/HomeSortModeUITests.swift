import XCTest

/// Phase 4 排序模式的 UI 验证。
///
/// 运行前需要首页已存在这样一组数据（由 test-phase4.sh 写入模拟器容器）：
/// - 2024.03（看过）：千与千寻 / 星际穿越 / 你想活出怎样的人生
/// - 2024.01（看过）：沙丘2
/// - 未设年份（想看）：阿诺拉
///
/// 这些断言会真实拖动卡片，是真机/模拟器上的端到端验证，不是逻辑单测。
final class HomeSortModeUITests: XCTestCase {

    private var app: XCUIApplication!

    private let group202403 = ["千与千寻", "星际穿越", "你想活出怎样的人生"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(card("千与千寻").waitForExistence(timeout: 10),
                      "首页没加载出测试数据，请先写入 Documents/SakuraReelLibrary.json")
    }

    // MARK: - 工具

    private func card(_ title: String) -> XCUIElement {
        app.staticTexts[title]
    }

    private func enterSortMode() {
        let button = app.buttons["排序"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "找不到「排序」按钮")
        button.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5), "没进入排序模式")
    }

    /// 按「先上下、后左右」比较两张卡片在网格中的先后
    private func isBefore(_ a: String, _ b: String) -> Bool {
        let fa = card(a).frame
        let fb = card(b).frame
        if abs(fa.minY - fb.minY) > 1 { return fa.minY < fb.minY }
        return fa.minX < fb.minX
    }

    private func assertOrder(_ titles: [String], _ stage: String) {
        for (i, earlier) in titles.enumerated() {
            for later in titles[(i + 1)...] {
                XCTAssertTrue(isBefore(earlier, later),
                              "[\(stage)] 期望「\(earlier)」在「\(later)」之前，实际网格：\(gridSnapshot())")
            }
        }
    }

    /// 失败时把当前网格顺序打进日志，便于定位
    private func gridSnapshot() -> String {
        let titles = ["千与千寻", "星际穿越", "你想活出怎样的人生", "沙丘2", "阿诺拉"]
        return titles
            .filter { card($0).exists }
            .sorted { isBefore($0, $1) }
            .joined(separator: " / ")
    }

    private func drag(_ from: String, onto to: String) {
        let source = card(from)
        let target = card(to)
        XCTAssertTrue(source.exists, "找不到卡片「\(from)」")
        XCTAssertTrue(target.exists, "找不到卡片「\(to)」")
        source.press(forDuration: 1.2, thenDragTo: target)
    }

    // MARK: - 1. 排序模式隐藏分类胶囊与 FAB

    func testSortModeHidesFiltersAndAddButton() {
        XCTAssertTrue(app.buttons["添加作品"].exists, "正常模式应显示 FAB")
        XCTAssertTrue(app.segmentedControls.firstMatch.exists, "正常模式应显示分类选择器")
        XCTAssertFalse(card("阿诺拉").exists, "正常模式「看过」筛选下不应显示想看条目")

        enterSortMode()

        XCTAssertFalse(app.buttons["添加作品"].exists, "排序模式应隐藏 FAB")
        XCTAssertEqual(app.segmentedControls.count, 0, "排序模式应隐藏分类选择器")
        XCTAssertFalse(app.buttons["搜索"].exists, "排序模式应隐藏搜索按钮")
        XCTAssertFalse(app.buttons["排序"].exists, "排序模式不应再有「排序」按钮")
        XCTAssertTrue(card("阿诺拉").exists, "排序模式应显示全部条目（含未设年份）")
    }

    // MARK: - 2. 同年同月组内拖动重排 → 完成后落盘并跨启动保持

    func testReorderWithinGroupThenCommitPersists() {
        assertOrder(group202403, "初始")
        enterSortMode()

        drag("你想活出怎样的人生", onto: "千与千寻")
        XCTAssertTrue(isBefore("你想活出怎样的人生", "千与千寻"),
                      "拖动后草稿顺序应已改变，实际：\(gridSnapshot())")

        app.buttons["完成"].tap()
        assertOrder(["你想活出怎样的人生", "千与千寻", "星际穿越"], "提交后")

        app.terminate()
        app.launch()
        XCTAssertTrue(card("千与千寻").waitForExistence(timeout: 10))
        assertOrder(["你想活出怎样的人生", "千与千寻", "星际穿越"], "重启后")
    }

    // MARK: - 3. 跨观看年月拖动被阻止并弹提示

    func testCrossGroupDragIsBlocked() {
        enterSortMode()
        assertOrder(group202403 + ["沙丘2", "阿诺拉"], "初始")

        // 2024.03 的卡片拖到 2024.01 的「沙丘2」上
        drag("千与千寻", onto: "沙丘2")

        let alert = app.alerts["无法移动"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "跨年月拖动应弹出提示")
        XCTAssertTrue(alert.staticTexts["只能调整相同观看年月内的作品顺序。"].exists,
                      "提示文案不符")
        alert.buttons["好"].tap()

        assertOrder(group202403 + ["沙丘2", "阿诺拉"], "阻止后")
    }

    // MARK: - 4. ✕ 放弃草稿并回滚

    func testCancelRollsBackReorder() {
        assertOrder(group202403, "初始")
        enterSortMode()

        drag("你想活出怎样的人生", onto: "千与千寻")
        XCTAssertTrue(isBefore("你想活出怎样的人生", "千与千寻"),
                      "拖动后草稿顺序应已改变，实际：\(gridSnapshot())")

        // 排序模式下导航栏左侧第一个按钮是 ✕
        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertOrder(group202403, "取消后")
    }

    // MARK: - 5. 排序模式下评分按钮不抢触摸

    func testRatingButtonIsInertInSortMode() {
        let reviewAlert = app.alerts["千与千寻  短评"]

        // 正常模式：点评分弹短评
        app.staticTexts["10"].tap()
        XCTAssertTrue(reviewAlert.waitForExistence(timeout: 3), "正常模式下点评分应弹出短评")
        reviewAlert.buttons["好"].tap()

        enterSortMode()
        app.staticTexts["10"].tap()
        XCTAssertFalse(reviewAlert.waitForExistence(timeout: 2),
                       "排序模式下评分按钮不应响应触摸")
        XCTAssertTrue(app.buttons["完成"].exists, "不应因点击卡片而退出排序模式")
    }
}
