import XCTest

final class ReminderPlanTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func schedule(_ id: String = "bysx") -> ScheduleData {
        ScheduleTemplate.all.first { $0.id == id }!.makeData(today: date(1), calendar: cal)
    }

    func testEveningReminderUsesNightShiftStartDay() throws {
        var data = schedule()
        data.eveningReminderEnabled = true
        let plan = data.plannedNotifications(from: date(1, 12), includeShiftAlarms: false, calendar: cal)
        let first = try XCTUnwrap(plan.first)
        XCTAssertEqual(first.kind, .evening)
        XCTAssertEqual(first.fireDate, date(1, 21))
        XCTAssertEqual(first.type.id, data.types[1].id)
    }

    func testEveningReminderForMidnightShift() throws {
        var data = schedule("4b3d")
        data.eveningReminderEnabled = true
        let plan = data.plannedNotifications(from: date(4, 18), includeShiftAlarms: false, calendar: cal)
        XCTAssertEqual(plan.first?.fireDate, date(4, 21))
        XCTAssertEqual(plan.first?.type.startMinutes, 0)
    }

    func testEveningOffDayOptOutAndCustomTime() {
        var data = schedule()
        data.eveningReminderEnabled = true
        data.eveningReminderMinutes = 19 * 60 + 30
        var plan = data.plannedNotifications(from: date(2, 12), includeShiftAlarms: false, calendar: cal)
        XCTAssertEqual(plan.first?.fireDate, date(2, 19, 30))
        XCTAssertEqual(plan.first?.type.isOff, true)
        data.remindOnOffDays = false
        plan = data.plannedNotifications(from: date(2, 12), includeShiftAlarms: false, calendar: cal)
        XCTAssertTrue(plan.allSatisfy { !$0.type.isOff })
        XCTAssertEqual(plan.first?.fireDate, date(4, 19, 30))
    }

    func testMergedNotificationsTakeNearestSixtyAcrossKinds() {
        var data = schedule("z6x1")
        data.reminderEnabled = true
        data.eveningReminderEnabled = true
        data.types[0].alarms = [ShiftAlarm(minutes: 6 * 60)]
        let now = date(1, 5)
        let plan = data.plannedNotifications(from: now, includeShiftAlarms: true, days: 200, limit: 500, calendar: cal)
        XCTAssertEqual(plan.count, 60)
        XCTAssertEqual(plan.first?.kind, .shiftAlarm)
        XCTAssertEqual(plan.first?.fireDate, date(1, 6))
        XCTAssertEqual(plan[1].kind, .beforeShift)
        XCTAssertEqual(plan[2].kind, .evening)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
        XCTAssertEqual(Set(plan.map(\.id)).count, 60)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now })
    }

    func testDisabledSettingsAndZeroLimitsAreSafe() {
        let data = schedule()
        XCTAssertTrue(data.plannedNotifications(from: date(1), includeShiftAlarms: true, calendar: cal).isEmpty)
        XCTAssertTrue(data.plannedNotifications(from: date(1), includeShiftAlarms: true, limit: 0, calendar: cal).isEmpty)
        XCTAssertTrue(data.plannedNotifications(from: date(1), includeShiftAlarms: true, days: -1, calendar: cal).isEmpty)
        XCTAssertTrue(data.plannedAlarms(from: date(1), days: 0, calendar: cal).isEmpty)
        XCTAssertTrue(data.upcomingReminders(from: date(1), limit: 0, calendar: cal).isEmpty)
    }

    func testMultipleAlarmsAndPreviousDay() {
        var data = schedule()
        data.types[1].alarms = [ShiftAlarm(minutes: 18 * 60 + 30, dayBefore: true),
                                ShiftAlarm(minutes: 19 * 60), ShiftAlarm(minutes: 19 * 60 + 10),
                                ShiftAlarm(minutes: 19 * 60 + 20, enabled: false)]
        let plan = data.plannedAlarms(from: date(1, 12), calendar: cal)
        XCTAssertEqual(Array(plan.prefix(3).map(\.fireDate)), [date(1, 18, 30), date(2, 19), date(2, 19, 10)])
        XCTAssertEqual(plan.first?.shiftStart, date(2, 20))
        XCTAssertTrue(plan.allSatisfy { $0.fireDate <= $0.shiftStart })
        XCTAssertTrue(plan.allSatisfy { $0.fireDate <= date(15, 12) })
    }

    func testAlarmsFollowOverrideAndSkipOffDaysAndInvalidTime() {
        var data = schedule()
        data.types[0].alarms = [ShiftAlarm(minutes: 6 * 60), ShiftAlarm(minutes: 6 * 60 + 10),
                                ShiftAlarm(minutes: 9 * 60)]
        data.types[2].alarms = [ShiftAlarm(minutes: 5 * 60)]
        data.setShift(data.types[0].id, on: date(3), calendar: cal)
        data.setShift(data.types[2].id, on: date(5), calendar: cal)
        let plan = data.plannedAlarms(from: date(2, 12), calendar: cal)
        XCTAssertEqual(Array(plan.prefix(2).map(\.fireDate)), [date(3, 6), date(3, 6, 10)])
        XCTAssertFalse(plan.contains { cal.isDate($0.fireDate, inSameDayAs: date(5)) })
        XCTAssertTrue(plan.allSatisfy { !$0.type.isOff })
    }

    func testTomorrowAlarmFiringTodayIncludedAtHorizonEdge() {
        var data = schedule("z6x1")
        data.types[0].alarms = [ShiftAlarm(minutes: 18 * 60 + 30, dayBefore: true)]
        let plan = data.plannedAlarms(from: date(1, 12), days: 1, calendar: cal)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.fireDate, date(1, 18, 30))
        XCTAssertEqual(plan.first?.shiftStart, date(2, 9))
    }

    func testAlarmLimitAndNotificationFallbackShareBudget() {
        var data = schedule("z6x1")
        data.types[0].alarms = (0..<12).map { ShiftAlarm(minutes: 300 + $0) }
        XCTAssertEqual(data.plannedAlarms(from: date(1), limit: 999, calendar: cal).count, 60)
        XCTAssertEqual(data.plannedNotifications(from: date(1), includeShiftAlarms: true, calendar: cal).count, 60)
        XCTAssertTrue(data.plannedNotifications(from: date(1), includeShiftAlarms: false, calendar: cal).isEmpty)
    }

    func testLiveShiftFindsPreviousOvernightAndNextAfterRest() {
        let data = schedule()
        let working = data.liveShift(from: date(3, 2), calendar: cal)
        XCTAssertEqual(working?.isWorking, true)
        XCTAssertEqual(working?.start, date(2, 20))
        XCTAssertEqual(working?.target, date(3, 8))
        let next = data.liveShift(from: date(3, 8), calendar: cal)
        XCTAssertEqual(next?.isWorking, false)
        XCTAssertEqual(next?.target, date(5, 8))
    }

    func testLiveShiftAllOffAndEmptyAreSafe() {
        var data = schedule()
        data.cycle = [data.types[2].id]
        XCTAssertNil(data.liveShift(from: date(1), calendar: cal))
        data.cycle = []
        XCTAssertNil(data.liveShift(from: date(1), calendar: cal))
    }

    func testDeletingOnlyUsedTypeKeepsEditableCycle() {
        var data = schedule()
        let first = data.types[0].id
        data.cycle = [first]
        data.removeType(id: first)
        XCTAssertFalse(data.cycle.isEmpty)
        XCTAssertNotNil(data.shift(on: date(1), calendar: cal))
        XCTAssertTrue(data.cycle.allSatisfy { data.type(id: $0) != nil })
    }

    func testOldArchiveWithoutAlarmOrPreferenceFieldsDecodes() throws {
        let data = schedule()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as! [String: Any]
        for key in ["eveningReminderEnabled", "eveningReminderMinutes", "remindOnOffDays", "alarmDelivery", "liveActivityEnabled"] {
            json.removeValue(forKey: key)
        }
        var types = json["types"] as! [[String: Any]]
        for index in types.indices { types[index].removeValue(forKey: "alarms") }
        json["types"] = types
        let decoded = try JSONDecoder().decode(ScheduleData.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, data)
        XCTAssertTrue(decoded.types.allSatisfy { $0.alarms.isEmpty })
        XCTAssertEqual(decoded.eveningReminderMinutes, 21 * 60)
        XCTAssertTrue(decoded.remindOnOffDays)
        XCTAssertFalse(decoded.liveActivityEnabled)
    }

    func testAlarmAndPreferencesRoundTrip() throws {
        var data = schedule()
        data.types[0].alarms = [ShiftAlarm(minutes: 360), ShiftAlarm(minutes: 370, enabled: false)]
        data.eveningReminderEnabled = true
        data.eveningReminderMinutes = 1230
        data.alarmDelivery = .notification
        data.liveActivityEnabled = true
        let decoded = try JSONDecoder().decode(ScheduleData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded, data)
        var replacement = schedule("4b3d")
        replacement.copyReminderSettings(from: data)
        XCTAssertEqual(replacement.eveningReminderMinutes, 1230)
        XCTAssertEqual(replacement.alarmDelivery, .notification)
        XCTAssertTrue(replacement.liveActivityEnabled)
    }

    func testShareCodeExcludesPersonalAlarmsAndSettings() throws {
        var data = schedule()
        data.types[0].alarms = [ShiftAlarm(minutes: 360)]
        data.eveningReminderEnabled = true
        data.liveActivityEnabled = true
        let imported = try XCTUnwrap(ShareCode.decode(ShareCode.message(for: data, calendar: cal), calendar: cal))
        XCTAssertTrue(imported.types.allSatisfy { $0.alarms.isEmpty })
        XCTAssertFalse(imported.eveningReminderEnabled)
        XCTAssertFalse(imported.liveActivityEnabled)
        XCTAssertEqual(imported.types.map(\.startMinutes), data.types.map(\.startMinutes))
    }

    func testWallClockTimesRemainCorrectAcrossDaylightSaving() throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "America/New_York")!
        let start = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        var data = ScheduleTemplate.all.first { $0.id == "z6x1" }!.makeData(today: start, calendar: local)
        data.types[0].alarms = [ShiftAlarm(minutes: 6 * 60)]
        let alarm = try XCTUnwrap(data.plannedAlarms(from: start, calendar: local).first)
        XCTAssertEqual(local.component(.hour, from: alarm.fireDate), 6)
        let interval = try XCTUnwrap(data.shiftInterval(on: start, calendar: local))
        XCTAssertEqual(local.component(.hour, from: interval.start), 9)
        XCTAssertEqual(local.component(.hour, from: interval.end), 18)
    }
}
