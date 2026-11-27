import Foundation

enum ShareCode {
    static let marker = "#班历#"

    private struct Payload: Codable {
        struct T: Codable {
            var n: String
            var k: String
            var a: Int
            var b: Int
            var o: Bool
        }

        var v: Int
        var n: String
        var s: String
        var t: [T]
        var c: [Int]
    }


    static func code(for data: ScheduleData, calendar: Calendar = .banli) -> String {
        var index: [UUID: Int] = [:]
        for (i, t) in data.types.enumerated() { index[t.id] = i }
        let payload = Payload(
            v: 1,
            n: data.templateName,
            s: DayKey.key(for: data.cycleStart, calendar: calendar),
            t: data.types.map { .init(n: $0.name, k: $0.colorHex, a: $0.startMinutes, b: $0.endMinutes, o: $0.isOff) },
            c: data.cycle.compactMap { index[$0] }
        )
        guard let json = try? JSONEncoder().encode(payload) else { return "" }
        let packed = (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
        return base64url(packed)
    }

    static func message(for data: ScheduleData, calendar: Calendar = .banli) -> String {
        String(localized: "我在用「班历」看排班，这是我们的排班（\(data.displayTemplateName)）。")
            + String(localized: "复制这整段话，打开「班历」点「粘贴」就能一键导入。还没装的在 App Store 搜「班历」。")
            + "\(marker)\(code(for: data, calendar: calendar))#"
    }


    static func decode(_ text: String, calendar: Calendar = .banli) -> ScheduleData? {
        guard text.count <= 6000, let start = text.range(of: marker) else { return nil }
        let rest = text[start.upperBound...]
        let raw = rest.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard !raw.isEmpty, let packed = fromBase64url(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let json = (try? (packed as NSData).decompressed(using: .zlib) as Data) ?? packed
        guard json.count <= 50_000,
              let p = try? JSONDecoder().decode(Payload.self, from: json),
              p.v == 1, !p.t.isEmpty, p.t.count <= 30, !p.c.isEmpty, p.c.count <= 400,
              p.c.allSatisfy({ (0..<p.t.count).contains($0) }),
              let startDate = parseDay(p.s, calendar: calendar) else { return nil }

        let types = p.t.map {
            ShiftType(name: String($0.n.prefix(20)), colorHex: String($0.k.prefix(8)),
                      startMinutes: (($0.a % 1440) + 1440) % 1440,
                      endMinutes: min(max($0.b, 0), 1440), isOff: $0.o)
        }
        return ScheduleData(
            types: types,
            cycle: p.c.map { types[$0].id },
            cycleStart: startDate,
            overrides: [:],
            reminderEnabled: false,
            reminderMinutesBefore: 60,
            templateName: String(p.n.prefix(30))
        )
    }


    private static func parseDay(_ s: String, calendar: Calendar) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func base64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func fromBase64url(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}
