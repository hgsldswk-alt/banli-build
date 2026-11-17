import XCTest

final class ShareCodeTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func source() -> ScheduleData {
        var d = ScheduleTemplate.all.first { $0.id == "4b3d" }!.makeData(today: day(2026, 11, 1), calendar: cal)
        d.types[0].name = "A班"
        d.types[0].colorHex = "EB5757"
        d.setShift(d.types[3].id, on: day(2026, 11, 3), calendar: cal)
        d.setNote("私人备注", on: day(2026, 11, 4), calendar: cal)        // 备注不应被分享
        return d
    }

    func testRoundTripKeepsSameShiftEveryDay() throws {
        let d = source()
        let msg = ShareCode.message(for: d, calendar: cal)
        XCTAssertTrue(msg.contains(ShareCode.marker))
        let back = try XCTUnwrap(ShareCode.decode(msg, calendar: cal))
        XCTAssertEqual(back.templateName, d.templateName)
        XCTAssertEqual(back.types.map(\.name), d.types.map(\.name))
        XCTAssertEqual(back.types.map(\.colorHex), d.types.map(\.colorHex))
        for i in -30..<400 {
            let date = cal.date(byAdding: .day, value: i, to: day(2026, 11, 1))!
            XCTAssertEqual(back.cycleShift(on: date, calendar: cal)?.name, d.cycleShift(on: date, calendar: cal)?.name, "\(i)")
        }
        XCTAssertTrue(back.overrides.isEmpty)
        XCTAssertTrue(back.notes.isEmpty)
    }

    func testFindsCodeInsideChatText() throws {
        let d = source()
        let pasted = "【班组群】老张：\n" + ShareCode.message(for: d, calendar: cal) + "\n大家导一下哈"
        let back = try XCTUnwrap(ShareCode.decode(pasted, calendar: cal))
        XCTAssertEqual(back.cycle.count, 8)
    }

    func testMessageIsReasonablyShort() {
        XCTAssertLessThan(ShareCode.message(for: source(), calendar: cal).count, 600)
    }

    func testRejectsGarbage() {
        XCTAssertNil(ShareCode.decode("随便一段话", calendar: cal))
        XCTAssertNil(ShareCode.decode("#班历#abc#", calendar: cal))
        XCTAssertNil(ShareCode.decode("#班历##", calendar: cal))
        XCTAssertNil(ShareCode.decode(String(repeating: "#班历#", count: 2000), calendar: cal))
    }
}
