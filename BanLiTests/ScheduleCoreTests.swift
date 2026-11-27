import XCTest

final class ScheduleCoreTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func twoShift() -> ScheduleData {
        ScheduleTemplate.all.first { $0.id == "bysx" }!.makeData(today: day(2026, 11, 1), calendar: cal)
    }

    func testCycleForwardAndBackward() {
        let d = twoShift()
        XCTAssertEqual(d.shift(on: day(2026, 11, 1), calendar: cal)?.name, String(localized: "白班"))
        XCTAssertEqual(d.shift(on: day(2026, 11, 2), calendar: cal)?.name, String(localized: "夜班"))
        XCTAssertEqual(d.shift(on: day(2026, 11, 3), calendar: cal)?.name, String(localized: "休息"))
        XCTAssertEqual(d.shift(on: day(2026, 11, 4), calendar: cal)?.name, String(localized: "休息"))
        XCTAssertEqual(d.shift(on: day(2026, 11, 5), calendar: cal)?.name, String(localized: "白班"))
        XCTAssertEqual(d.shift(on: day(2026, 10, 31), calendar: cal)?.name, String(localized: "休息"))
        XCTAssertEqual(d.shift(on: day(2026, 10, 29), calendar: cal)?.name, String(localized: "夜班"))
        XCTAssertEqual(d.shift(on: day(2026, 11, 2, 23, 59), calendar: cal)?.name, String(localized: "夜班"))
        XCTAssertEqual(d.cycleIndex(on: day(2027, 1, 1), calendar: cal), 61 % 4)
    }

    func testOverrideAndReset() {
        var d = twoShift()
        let target = day(2026, 11, 3)
        let white = d.types.first { $0.name == String(localized: "白班") }!
        d.setShift(white.id, on: target, calendar: cal)
        XCTAssertTrue(d.isOverridden(target, calendar: cal))
        XCTAssertEqual(d.shift(on: target, calendar: cal)?.name, String(localized: "白班"))
        XCTAssertEqual(d.cycleShift(on: target, calendar: cal)?.name, String(localized: "休息"))

        let off = d.types.first { $0.isOff }!
        d.setShift(off.id, on: target, calendar: cal)
        XCTAssertFalse(d.isOverridden(target, calendar: cal))
        XCTAssertTrue(d.overrides.isEmpty)
    }

    func testSetTodayPosition() {
        var d = twoShift()
        let today = day(2026, 11, 20, 15)
        d.setToday(isCycleDay: 1, today: today, calendar: cal)
        XCTAssertEqual(d.shift(on: today, calendar: cal)?.name, String(localized: "夜班"))
        XCTAssertEqual(d.shift(on: day(2026, 11, 21), calendar: cal)?.name, String(localized: "休息"))
        XCTAssertEqual(d.shift(on: day(2026, 11, 19), calendar: cal)?.name, String(localized: "白班"))
    }

    func testRemoveTypeCleansCycleAndOverrides() {
        var d = twoShift()
        let night = d.types.first { $0.name == String(localized: "夜班") }!
        d.setShift(night.id, on: day(2026, 11, 3), calendar: cal)
        d.removeType(id: night.id)
        XCTAssertEqual(d.cycle.count, 3)
        XCTAssertTrue(d.overrides.isEmpty)
        XCTAssertNil(d.type(id: night.id))
    }

    func testCycleRunsRoundTrip() {
        var data = ScheduleTemplate.all.first { $0.id == "4b3d" }!.makeData(today: day(2026, 11, 1), calendar: cal)
        let ids = data.types.map(\.id)
        XCTAssertEqual(data.cycleRuns.map(\.count), [2, 2, 2, 2])
        XCTAssertEqual(data.cycleRuns.map(\.typeID), ids)

        data.cycleRuns = [CycleRun(typeID: ids[0], count: 3), CycleRun(typeID: ids[3], count: 2)]
        XCTAssertEqual(data.cycle, [ids[0], ids[0], ids[0], ids[3], ids[3]])
        XCTAssertEqual(data.shift(on: day(2026, 11, 4), calendar: cal)?.id, ids[3])
        XCTAssertEqual(data.shift(on: day(2026, 11, 6), calendar: cal)?.id, ids[0])

        data.cycleRuns = [CycleRun(typeID: ids[1], count: 0)]
        XCTAssertEqual(data.cycle, [ids[1]])
        data.cycleRuns = []
        XCTAssertEqual(data.cycle, [ids[1]])
    }

    func testEmptyCycleIsSafe() {
        var d = twoShift()
        d.cycle = []
        XCTAssertNil(d.shift(on: day(2026, 11, 1), calendar: cal))
        XCTAssertTrue(d.upcomingReminders(from: day(2026, 11, 1), calendar: cal).isEmpty)
    }

    func testMonthStats() {
        let d = twoShift()
        let stats = d.monthStats(for: day(2026, 11, 15), calendar: cal)
        let total = stats.reduce(0) { $0 + $1.days }
        XCTAssertEqual(total, 30)
        XCTAssertEqual(stats.first { $0.type.name == String(localized: "白班") }?.days, 8)
        XCTAssertEqual(stats.first { $0.type.name == String(localized: "夜班") }?.days, 8)
        XCTAssertEqual(stats.first { $0.type.name == String(localized: "休息") }?.days, 14)
    }

    func testRemindersSkipOffDaysAndPast() {
        var d = twoShift()
        d.reminderMinutesBefore = 60
        let now = day(2026, 11, 1, 10)
        let r = d.upcomingReminders(from: now, days: 8, calendar: cal)
        XCTAssertEqual(r.first?.type.name, String(localized: "夜班"))
        XCTAssertEqual(r.first?.fireDate, day(2026, 11, 2, 19))
        XCTAssertTrue(r.allSatisfy { !$0.type.isOff })
        XCTAssertTrue(r.allSatisfy { $0.fireDate > now })
        XCTAssertEqual(r.count, 4)
    }

    func testReminderLimit() {
        let d = ScheduleTemplate.all.first { $0.id == "z6x1" }!.makeData(today: day(2026, 11, 1), calendar: cal)
        XCTAssertEqual(d.upcomingReminders(from: day(2026, 11, 1), days: 200, limit: 60, calendar: cal).count, 60)
    }

    func testAllTemplatesValid() {
        for t in ScheduleTemplate.all {
            let d = t.makeData(today: day(2026, 11, 1), calendar: cal)
            XCTAssertEqual(d.cycle.count, t.pattern.count, t.name)
            XCTAssertTrue(d.cycle.allSatisfy { d.type(id: $0) != nil }, t.name)
            XCTAssertEqual(d.cycle.map { d.type(id: $0)!.name }, t.patternNames, t.name)
        }
    }

    func testCodableRoundTrip() throws {
        var d = twoShift()
        d.setShift(d.types[0].id, on: day(2026, 11, 3), calendar: cal)
        let decoded = try JSONDecoder().decode(ScheduleData.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(decoded, d)
    }

    func testClockText() {
        XCTAssertEqual(ShiftType.clock(0), "00:00")
        XCTAssertEqual(ShiftType.clock(20 * 60 + 5), "20:05")
        XCTAssertEqual(ShiftType.clock(24 * 60), "00:00")
        XCTAssertEqual(DayKey.key(for: day(2026, 1, 9), calendar: cal), "2026-01-09")
    }
}
