import XCTest

final class ICSExportTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testOneEventPerWorkDayAndSkipsOffDays() throws {
        let data = ScheduleTemplate.all.first { $0.id == "4b3d" }!.makeData(today: day(2026, 11, 1), calendar: cal)
        let start = day(2026, 11, 1)
        let ics = ICSExport.text(for: data, from: start, days: 28, calendar: cal)
        let work = (0..<28).filter { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            return data.shift(on: d, calendar: cal).map { !$0.isOff } ?? false
        }.count
        XCTAssertGreaterThan(work, 0)
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, work)
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
    }

    func testOvernightShiftEndsNextDay() throws {
        var data = ScheduleTemplate.all.first { $0.id == "4b3d" }!.makeData(today: day(2026, 11, 1), calendar: cal)
        let night = ShiftType(name: "夜班", colorHex: "#334455", startMinutes: 20 * 60, endMinutes: 8 * 60)
        data.types.append(night)
        data.setShift(night.id, on: day(2026, 11, 3), calendar: cal)
        let ics = ICSExport.text(for: data, from: day(2026, 11, 3), days: 1, calendar: cal)
        XCTAssertTrue(ics.contains("DTSTART:20261103T200000"), ics)
        XCTAssertTrue(ics.contains("DTEND:20261104T080000"), ics)
        XCTAssertTrue(ics.contains("SUMMARY:夜班"), ics)
    }

    func testEscapesSpecialCharacters() {
        XCTAssertEqual(ICSExport.escape("A,B;C\\D\nE"), "A\\,B\\;C\\\\D\\nE")
    }
}
