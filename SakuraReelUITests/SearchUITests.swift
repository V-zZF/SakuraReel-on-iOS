import XCTest

/// Phase 6 搜索的 UI 验证。
///
/// 运行前需要首页已存在这样一组数据（由 Scripts/run-ui-tests.sh 写入模拟器容器，
/// 与 HomeSortModeUITests 共用同一份 home fixture）：
/// - 2024.03（看过）：千与千寻 / 星际穿越 / 你想活出怎样的人生
/// - 2024.01（看过）：沙丘2
/// - 未设年份（想看）：阿诺拉
///
/// Phase 6 验收时确认的两条既定行为（**本次未改动**，只用用例把现状钉住）：
/// - 只匹配片名，不搜短评
/// - 忽略当前分类胶囊，跨「看过 / 在看 / 想看」全局搜
final class SearchUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["千与千寻"].waitForExistence(timeout: 10),
                      "首页没加载出测试数据，请先写入 Documents/SakuraReelLibrary.json")
    }

    // MARK: - 工具

    /// 点胶囊行右端的放大镜进入搜索，输入关键词
    private func search(_ keyword: String) {
        app.buttons["搜索"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "点放大镜后应出现搜索输入框")
        // 手写搜索栏不会自动聚焦，得先点一下
        field.tap()
        field.typeText(keyword)
    }

    /// 等元素从视图树里消失。
    ///
    /// 搜索栏是带滑出动画的，动画期间元素仍在树里 —— 立即断言会和动画抢时间。
    /// 这里手写轮询而不用 `waitForExpectations`：那个方法会把 `self` 送过隔离边界，
    /// 在 Swift 6 严格并发下编译不过。
    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    // MARK: - 1. 未点放大镜时没有搜索框；输入后实时过滤

    func testSearchFiltersLive() {
        XCTAssertFalse(app.textFields.firstMatch.exists, "未点放大镜时不应有搜索框")

        search("千与")

        XCTAssertTrue(app.staticTexts["千与千寻"].exists, "「千与」应命中「千与千寻」")
        XCTAssertFalse(app.staticTexts["星际穿越"].exists, "未命中的条目应被过滤掉")
        XCTAssertFalse(app.staticTexts["你想活出怎样的人生"].exists, "未命中的条目应被过滤掉")
    }

    // MARK: - 2. 搜索忽略分类胶囊，跨分类全局搜

    func testSearchSpansCategories() {
        // 「阿诺拉」是「想看」，当前胶囊停在「看过」，默认看不到它
        XCTAssertFalse(app.staticTexts["阿诺拉"].exists, "「看过」筛选下不该出现想看条目")

        search("阿诺拉")

        XCTAssertTrue(app.staticTexts["阿诺拉"].exists, "搜索应跨分类命中「想看」的条目")
        XCTAssertFalse(app.staticTexts["千与千寻"].exists, "未命中的条目应被过滤掉")
    }

    // MARK: - 3. 没有命中时显示「无搜索结果」空态

    func testSearchWithNoMatchShowsEmptyState() {
        search("不存在的片名")

        XCTAssertTrue(app.staticTexts["无搜索结果"].waitForExistence(timeout: 5),
                      "没有命中时应显示「无搜索结果」，而不是「还没有作品」")
        XCTAssertFalse(app.staticTexts["千与千寻"].exists, "没有命中时不应有卡片")
    }

    // MARK: - 4. 取消退出搜索并恢复全量

    func testCancelRestoresFullGrid() {
        search("千与")
        XCTAssertFalse(app.staticTexts["星际穿越"].exists, "搜索中应处于过滤状态")

        app.buttons["取消"].tap()

        waitForDisappearance(app.textFields.firstMatch)
        XCTAssertFalse(app.textFields.firstMatch.exists, "取消后搜索框应消失")
        XCTAssertTrue(app.staticTexts["星际穿越"].waitForExistence(timeout: 5),
                      "取消后应恢复显示全部条目")
        XCTAssertTrue(app.staticTexts["千与千寻"].exists)
    }
}
