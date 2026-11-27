import Foundation

enum ICSExport {
    static func text(for data: ScheduleData, from: Date, days: Int = 90, calendar: Calendar = .banli) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//BanLi//Shift Calendar//EN", "CALSCALE:GREGORIAN", "X-WR-CALNAME:BanLi"]
        let stamp = stampFormatter.string(from: from)
        let start = calendar.startOfDay(for: from)
        for i in 0..<max(days, 0) {
            guard let day = calendar.date(byAdding: .day, value: i, to: start),
                  let t = data.shift(on: day, calendar: calendar), !t.isOff,
                  let span = data.shiftInterval(on: day, calendar: calendar) else { continue }
            let f = localFormatter(calendar)
            lines += [
                "BEGIN:VEVENT",
                "UID:banli-\(DayKey.key(for: day, calendar: calendar))-\(t.id.uuidString)",
                "DTSTAMP:\(stamp)",
                "DTSTART:\(f.string(from: span.start))",
                "DTEND:\(f.string(from: span.end))",
                "SUMMARY:\(escape(t.name))",
                "END:VEVENT",
            ]
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func file(for data: ScheduleData, from: Date, days: Int = 90) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BanLi.ics")
        do {
            try text(for: data, from: from, days: days).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func localFormatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()
}
