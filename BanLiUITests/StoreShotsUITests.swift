import XCTest

final class StoreShotsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true; executionTimeAllowance = 1800 }

    private let languages: [(code: String, locale: String)] = [("zh-Hans", "zh_CN"), ("en", "en_US"), ("zh-Hant", "zh_TW"), ("ja", "ja_JP"), ("de", "de_DE")]
    private let pages: [(name: String, args: [String])] = [
        ("1-home", []),
        ("2-settings", ["-tab", "1"]),
        ("3-picker", ["-tab", "1", "-picker"]),
        ("4-editor", ["-tab", "1", "-cycle"]),
        ("5-onboarding", ["-onboarding"]),
        ("6-reminders", ["-tab", "1", "-reminders"]),
        ("7-alarms", ["-tab", "1", "-alarms"]),
        ("8-paywall", ["-paywall"])
    ]

    func testStoreScreenshots() throws {
        for language in languages {
            for page in pages {
                let app = XCUIApplication()
                app.launchArguments = ["-demo"] + page.args + ["-AppleLanguages", "(" + language.code + ")", "-AppleLocale", language.locale]
                app.launch()
                _ = app.wait(for: .runningForeground, timeout: 10)
                Thread.sleep(forTimeInterval: 4)
                let attachment = XCTAttachment(data: app.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
                attachment.name = "store-" + language.code + "-" + page.name
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
    }
}
