import XCTest

final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let att = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        att.name = name
        att.lifetime = .keepAlways
        add(att)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func waitUntil(_ cond: @escaping () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(6)
        while Date() < end {
            if cond() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return cond()
    }

    private func openSettings() {
        let tab = app.tabBars.buttons["设置"].exists ? app.tabBars.buttons["设置"] : app.buttons["设置"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
    }

    func testCreateFromTemplate() {
        openSettings()
        shot("01-settings")

        app.staticTexts["排班方式"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["我的排班"].waitForExistence(timeout: 5), "选择排班方式页没出来")
        XCTAssertTrue(app.staticTexts["从模板新建"].exists)
        shot("02-picker")

        app.staticTexts["两班倒（白夜休休）"].firstMatch.tap()
        let save = app.buttons["saveSchedule"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "编辑页没打开")
        XCTAssertEqual(save.label, "保存并使用")
        shot("03-editor-new")

        let day3 = app.descendants(matching: .any)["cycleDay-2"]
        XCTAssertTrue(day3.waitForExistence(timeout: 3), "循环预览色块找不到")
        day3.tap()
        XCTAssertTrue(app.staticTexts["今天是第 3 天：休息"].waitForExistence(timeout: 3), "点选今天没生效")
        shot("04-editor-today")

        save.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == '保存并使用' AND identifier != 'saveSchedule'")).firstMatch
        if confirm.waitForExistence(timeout: 3) {
            shot("04b-confirm-clear-overrides")
            confirm.tap()
        }
        XCTAssertTrue(waitUntil { !save.exists }, "保存后编辑页没关掉")
        XCTAssertTrue(waitUntil { self.app.staticTexts.matching(identifier: "两班倒（白夜休休）").count >= 2 },
                      "我的排班里没出现新建的这套")
        shot("05-picker-after-save")
    }

    func testEditCurrent() {
        openSettings()
        app.buttons["改当前排班：天数、上下班时间"].firstMatch.tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "改当前排班的编辑页没打开")
        shot("06-edit-current")

        name.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let old = (name.value as? String) ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 4))
        name.typeText("我的四班")
        shot("06b-renamed-in-editor")
        let save = app.buttons["saveSchedule"]
        XCTAssertEqual(save.label, "保存", "改当前排班的按钮应该是「保存」")
        save.tap()
        let renamed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '我的四班'")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5), "改名后设置页没更新")
        shot("07-settings-renamed")
    }

    func testEditAndDeleteSaved() {
        openSettings()
        app.staticTexts["排班方式"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["A 组（上三休二）"].waitForExistence(timeout: 5))
        app.buttons["editSchedule"].firstMatch.tap()
        XCTAssertTrue(app.buttons["saveSchedule"].waitForExistence(timeout: 5), "铅笔没打开编辑页")
        let delete = app.buttons["删除这套排班"]
        for _ in 0..<6 where !delete.exists { app.swipeUp() }
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "编辑页底部没有删除按钮")
        shot("08-edit-saved")
        app.buttons["删除这套排班"].tap()
        let confirm = app.buttons["删除"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(waitUntil { !self.app.staticTexts["A 组（上三休二）"].exists }, "删除后还在")
        shot("09-after-delete")
    }
}
