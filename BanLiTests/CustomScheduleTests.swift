import XCTest

final class CustomScheduleTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testBlankIsThreeOnTwoOff() {
        let c = CustomSchedule.blank(name: "A")
        XCTAssertEqual(c.cycle.count, 5)
        XCTAssertEqual(c.runs.map(\.count), [3, 2])
        XCTAssertFalse(c.types[0].isOff)
        XCTAssertTrue(c.types[1].isOff)
    }

    func testRunsEditing() {
        var c = CustomSchedule.blank(name: "A")
        let work = c.types[0].id, off = c.types[1].id
        c.runs = [CycleRun(typeID: work, count: 4), CycleRun(typeID: off, count: 3)]
        XCTAssertEqual(c.cycle.count, 7)
        c.runs = []
        XCTAssertEqual(c.cycle.count, 7)
        c.runs = [CycleRun(typeID: work, count: 0)]
        XCTAssertEqual(c.cycle, [work])
    }

    func testRemoveTypeKeepsAtLeastOne() {
        var c = CustomSchedule.blank(name: "A")
        let work = c.types[0].id, off = c.types[1].id
        c.removeType(id: work)
        XCTAssertEqual(c.types.map(\.id), [off])
        XCTAssertEqual(c.cycle, [off, off])
        c.removeType(id: off)
        XCTAssertEqual(c.types.count, 1)
        XCTAssertFalse(c.cycle.isEmpty)
    }

    func testTodayIndexFromCycleStart() {
        var c = CustomSchedule.blank(name: "A")   // 5 天一循环
        XCTAssertEqual(c.todayIndex(now: day(2026, 11, 13), calendar: cal), 0)
        c.cycleStart = day(2026, 11, 10)
        XCTAssertEqual(c.todayIndex(now: day(2026, 11, 13), calendar: cal), 3)
        XCTAssertEqual(c.todayIndex(now: day(2026, 11, 16), calendar: cal), 1)
        XCTAssertEqual(c.todayIndex(now: day(2026, 11, 9), calendar: cal), 4)
    }

    func testDefaultNameAvoidsDuplicates() {
        let base = String(localized: "我的排班")
        XCTAssertEqual(CustomSchedule.defaultName(existing: []), base)
        let list = [CustomSchedule.blank(name: base), CustomSchedule.blank(name: "\(base) 2")]
        XCTAssertEqual(CustomSchedule.defaultName(existing: list), "\(base) 3")
    }

    func testFromTemplateCopiesShiftsAndCycle() {
        let t = ScheduleTemplate.all.first { $0.id == "4b3d" }!
        let c = CustomSchedule.from(t)
        XCTAssertEqual(c.name, t.name)
        XCTAssertEqual(c.cycle.count, 8)
        XCTAssertEqual(c.types.count, 4)
        XCTAssertNil(c.cycleStart)
    }

    func testCodableRoundTripAndOldDataWithoutCustomID() throws {
        var c = CustomSchedule.blank(name: "A 组")
        c.cycleStart = day(2026, 11, 1)
        let back = try JSONDecoder().decode(CustomSchedule.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)

        var data = ScheduleTemplate.all[0].makeData()
        data.customID = UUID()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as! [String: Any]
        json.removeValue(forKey: "customID")
        let old = try JSONDecoder().decode(ScheduleData.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.customID)
        XCTAssertEqual(old.cycle, data.cycle)
    }
}
