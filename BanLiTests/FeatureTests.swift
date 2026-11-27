import XCTest

final class FeatureTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func template(_ id: String, start: Date) -> ScheduleData {
        ScheduleTemplate.all.first { $0.id == id }!.makeData(today: start, calendar: cal)
    }


    func testDurations() {
        XCTAssertEqual(ShiftType(name: "白", colorHex: "000", startMinutes: 480, endMinutes: 1200).durationMinutes, 720)
        XCTAssertEqual(ShiftType(name: "夜", colorHex: "000", startMinutes: 1200, endMinutes: 480).durationMinutes, 720)
        XCTAssertEqual(ShiftType(name: "中", colorHex: "000", startMinutes: 960, endMinutes: 1440).durationMinutes, 480)
        XCTAssertEqual(ShiftType(name: "全", colorHex: "000", startMinutes: 480, endMinutes: 480).durationMinutes, 1440)
        XCTAssertEqual(ShiftType(name: "休", colorHex: "000", isOff: true).durationMinutes, 0)
    }

    func testMonthWorkMinutes() {
        let d = template("bysx", start: day(2026, 11, 1))
        XCTAssertEqual(d.monthWorkMinutes(for: day(2026, 11, 10), calendar: cal), 192 * 60)
    }

    func testShiftIntervalCrossesMidnight() {
        let d = template("bysx", start: day(2026, 11, 1))
        let iv = d.shiftInterval(on: day(2026, 11, 2), calendar: cal)!
        XCTAssertEqual(iv.start, day(2026, 11, 2, 20))
        XCTAssertEqual(iv.end, day(2026, 11, 3, 8))
        XCTAssertNil(d.shiftInterval(on: day(2026, 11, 3), calendar: cal))
    }


    func testNotes() {
        var d = template("bysx", start: day(2026, 11, 1))
        d.setNote("  和小王换班 ", on: day(2026, 11, 5), calendar: cal)
        XCTAssertEqual(d.note(on: day(2026, 11, 5, 18), calendar: cal), "和小王换班")
        d.setNote("   ", on: day(2026, 11, 5), calendar: cal)
        XCTAssertNil(d.note(on: day(2026, 11, 5), calendar: cal))
        XCTAssertTrue(d.notes.isEmpty)
    }

    func testDecodesDataWithoutNewFields() throws {
        let d = template("bysx", start: day(2026, 11, 1))
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as! [String: Any]
        obj.removeValue(forKey: "notes")
        obj.removeValue(forKey: "templateName")
        let old = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(ScheduleData.self, from: old)
        XCTAssertEqual(decoded.cycle, d.cycle)
        XCTAssertTrue(decoded.notes.isEmpty)
        XCTAssertEqual(decoded.templateName, String(localized: "自定义"))
    }


    func testBundledHolidays() {
        XCTAssertEqual(Holidays.info(for: day(2026, 10, 1), calendar: cal)?.name, "国庆节")
        XCTAssertEqual(Holidays.info(for: day(2026, 10, 1), calendar: cal)?.isOffDay, true)
        XCTAssertEqual(Holidays.info(for: day(2026, 2, 14), calendar: cal)?.isOffDay, false)
        XCTAssertEqual(Holidays.info(for: day(2027, 2, 5), calendar: cal)?.name, "春节")
        XCTAssertEqual(Holidays.info(for: day(2027, 9, 26), calendar: cal)?.isOffDay, false)
        XCTAssertNil(Holidays.info(for: day(2026, 11, 11), calendar: cal))
        let off2026: Int = Holidays.bundled[2026]?.filter { $0.isOffDay }.count ?? 0
        let off2027: Int = Holidays.bundled[2027]?.filter { $0.isOffDay }.count ?? 0
        XCTAssertEqual(off2026, 33)
        XCTAssertEqual(off2027, 29)
    }

    func testParseRemoteHolidayFile() {
        let json = #"{"year":2028,"papers":[],"days":[{"name":"元旦","date":"2028-01-01","isOffDay":true}]}"#
        let parsed = Holidays.parse(Data(json.utf8))
        XCTAssertEqual(parsed?.year, 2028)
        XCTAssertEqual(parsed?.days.first?.name, "元旦")
        XCTAssertNil(Holidays.parse(Data("not json".utf8)))
    }

    func testLunar() {
        let firstMonth = String(localized: "正") + String(localized: "月")
        let lastMonth = String(localized: "腊") + String(localized: "月")
        let newYear = String(localized: "农历") + firstMonth + String(localized: "初一")
        let newYearsEve = String(localized: "农历") + lastMonth + String(localized: "廿九")
        XCTAssertEqual(Lunar.shortText(day(2026, 2, 17, 12)), firstMonth)
        XCTAssertEqual(Lunar.fullText(day(2026, 2, 17, 12)), newYear)
        XCTAssertEqual(Lunar.fullText(day(2026, 2, 16, 12)), newYearsEve)
        XCTAssertEqual(Lunar.shortText(day(2026, 9, 25, 12)), String(localized: "十五")) // 中秋
    }


    private func weather(start: Date, rainAt rainHours: Set<Int>, temp: Double = 15, fetched: Date? = nil) -> WeatherSnapshot {
        let hours = (0..<48).map { i in
            WeatherSnapshot.Hour(date: cal.date(byAdding: .hour, value: i, to: start)!,
                                 temperature: temp, precipitationChance: rainHours.contains(i) ? 0.8 : 0.0,
                                 symbol: "cloud", condition: "多云")
        }
        let days = (0..<3).map { i in
            WeatherSnapshot.Day(date: cal.date(byAdding: .day, value: i, to: start)!,
                                high: temp + 3, low: temp - 3, precipitationChance: 0.1,
                                symbol: "sun.max", condition: "晴")
        }
        return WeatherSnapshot(hours: hours, days: days, fetchedAt: fetched ?? start, place: nil,
                               markLightURL: nil, markDarkURL: nil, legalURL: nil)
    }

    func testRainTipBeforeNightShift() {
        let d = template("bysx", start: day(2026, 11, 1)) // 11/2 夜班 20:00–08:00
        let now = day(2026, 11, 2, 15)
        let w = weather(start: day(2026, 11, 2), rainAt: [32], fetched: now)
        let tips = TipEngine.tips(data: d, now: now, weather: w, calendar: cal)
        XCTAssertTrue(tips.contains { $0.id == "rain" && $0.text.contains("08:00") })
        XCTAssertTrue(tips.contains { $0.id == "night" })
        XCTAssertLessThanOrEqual(tips.count, 3)
    }

    func testColdTip() {
        let d = template("bysx", start: day(2026, 11, 1)) // 11/1 白班 08:00–20:00
        let now = day(2026, 11, 1, 6)
        let tips = TipEngine.tips(data: d, now: now, weather: weather(start: day(2026, 11, 1), rainAt: [], temp: 2, fetched: now), calendar: cal)
        XCTAssertTrue(tips.contains { $0.id == "cold" })
    }

    func testStaleWeatherIgnoredAndFallback() {
        let d = template("bysx", start: day(2026, 11, 1))
        let old = weather(start: day(2026, 10, 1), rainAt: Set(0..<48))
        let tips = TipEngine.tips(data: d, now: day(2026, 11, 1, 6), weather: old, calendar: cal)
        XCTAssertFalse(tips.contains { $0.id == "rain" })
        XCTAssertFalse(tips.isEmpty)
    }

    func testAfterNightShiftRest() {
        let d = template("bysx", start: day(2026, 11, 1)) // 11/3 休息，前一天夜班
        let tips = TipEngine.tips(data: d, now: day(2026, 11, 3, 10), weather: nil, calendar: cal)
        XCTAssertEqual(tips.first?.id, "afterNight")
    }

    func testHolidayTipWhenWorking() {
        let d = template("z6x1", start: day(2026, 10, 1)) // 10/1 白班
        let tips = TipEngine.tips(data: d, now: day(2026, 10, 1, 7), weather: nil, calendar: cal,
                                  features: LocaleFeatures(language: "zh-Hans", region: "CN"))
        XCTAssertTrue(tips.contains { $0.id == "holiday" })
    }

    func testEarlyTomorrow() {
        var d = template("bysx", start: day(2026, 11, 1))
        d.types[0].startMinutes = 6 * 60 + 30
        let tips = TipEngine.tips(data: d, now: day(2026, 11, 4, 20), weather: nil, calendar: cal)
        XCTAssertTrue(tips.contains { $0.id == "earlyTomorrow" && $0.text.contains("06:30") })
    }
}
