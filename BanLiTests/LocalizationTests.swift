import XCTest

final class LocalizationTests: XCTestCase {
    func testSimplifiedChineseShowsLunarAndChinaHolidays() {
        for language in ["zh-Hans", "zh-Hans-US", "zh-CN", "zh-SG"] {
            let features = LocaleFeatures(language: language, region: "US")
            XCTAssertTrue(features.showsLunar, language)
            XCTAssertTrue(features.showsChinaHolidays, language)
        }
    }

    func testTraditionalChineseOutsideMainlandShowsOnlyLunar() {
        for language in ["zh-Hant", "zh-Hant-TW", "zh-TW", "zh-HK", "zh-MO"] {
            let features = LocaleFeatures(language: language, region: "TW")
            XCTAssertTrue(features.showsLunar, language)
            XCTAssertFalse(features.showsChinaHolidays, language)
        }
    }

    func testTraditionalChineseInMainlandShowsChinaHolidays() {
        let features = LocaleFeatures(language: "zh-Hant", region: "CN")
        XCTAssertTrue(features.showsLunar)
        XCTAssertTrue(features.showsChinaHolidays)
    }

    func testEnglishHidesChineseFeaturesInEveryRegion() {
        for region in ["US", "TW", "CN"] {
            let features = LocaleFeatures(language: "en", region: region)
            XCTAssertFalse(features.showsLunar)
            XCTAssertFalse(features.showsChinaHolidays)
        }
    }

    func testLegacyAndImportedBuiltInNamesUseCurrentLanguage() {
        let day = String(localized: "白班")
        for name in ["白班", "Day shift", "日班"] {
            let shift = ShiftType(name: name, colorHex: "F2994A")
            XCTAssertEqual(shift.displayName, day)
            XCTAssertEqual(shift.name, name)
        }
        XCTAssertEqual(BuiltInNames.localized("4-Crew (2Early·2Late·2N·2Off)"), String(localized: "四班三倒"))
        XCTAssertEqual(BuiltInNames.localized("Team A"), "Team A")
        XCTAssertEqual(BuiltInNames.localized("自訂班次甲"), "自訂班次甲")
    }

    func testEnglishTipsOmitChinaHolidays() {
        let cal = Calendar.banli
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 7))!
        let data = ScheduleTemplate.all.first { $0.id == "z6x1" }!.makeData(today: date, calendar: cal)
        let tips = TipEngine.tips(data: data, now: date, weather: nil, calendar: cal,
                                  features: LocaleFeatures(language: "en", region: "CN"))
        XCTAssertFalse(tips.contains { ["holiday", "makeup"].contains($0.id) })
        XCTAssertFalse(tips.isEmpty)
    }

    func testLegacyShareCodeDecodesWithForeignSurroundingText() throws {
        let data = ScheduleTemplate.all[0].makeData()
        let code = ShareCode.code(for: data)
        XCTAssertEqual(ShareCode.marker, "#班历#")
        for message in ["Import this rotation ", "匯入此班表 ", "导入这个排班 "] {
            let imported = try XCTUnwrap(ShareCode.decode(message + "#班历#" + code + "#"))
            XCTAssertEqual(imported.types.map(\.name), data.types.map(\.name))
            XCTAssertEqual(imported.cycle.count, data.cycle.count)
        }
    }
}
