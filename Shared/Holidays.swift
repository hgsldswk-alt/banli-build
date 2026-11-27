import Foundation

struct HolidayDay: Codable, Equatable {
    let name: String
    var displayName: String { BuiltInNames.localized(name) }
    let date: String
    let isOffDay: Bool
}

enum Holidays {

    private static func off(_ name: String, _ dates: [String]) -> [HolidayDay] {
        dates.map { HolidayDay(name: name, date: $0, isOffDay: true) }
    }

    private static func work(_ name: String, _ dates: [String]) -> [HolidayDay] {
        dates.map { HolidayDay(name: name, date: $0, isOffDay: false) }
    }

    private static func range(_ year: Int, _ month: Int, _ from: Int, _ to: Int) -> [String] {
        (from...to).map { String(format: "%04d-%02d-%02d", year, month, $0) }
    }

    static let bundled: [Int: [HolidayDay]] = [
        2026: off("元旦", range(2026, 1, 1, 3)) + work("元旦", ["2026-01-04"])
            + off("春节", range(2026, 2, 15, 23)) + work("春节", ["2026-02-14", "2026-02-28"])
            + off("清明节", range(2026, 4, 4, 6))
            + off("劳动节", range(2026, 5, 1, 5)) + work("劳动节", ["2026-05-09"])
            + off("端午节", range(2026, 6, 19, 21))
            + off("中秋节", range(2026, 9, 25, 27))
            + off("国庆节", range(2026, 10, 1, 7)) + work("国庆节", ["2026-09-20", "2026-10-10"]),
        2027: off("元旦", range(2027, 1, 1, 3))
            + off("春节", range(2027, 2, 5, 13)) + work("春节", ["2027-01-31", "2027-02-14"])
            + off("清明节", range(2027, 4, 3, 5))
            + off("劳动节", range(2027, 5, 1, 5)) + work("劳动节", ["2027-05-08"])
            + off("端午节", ["2027-06-09"])
            + off("中秋节", ["2027-09-15"])
            + off("国庆节", range(2027, 10, 1, 7)) + work("国庆节", ["2027-09-26", "2027-10-09"]),
    ]


    private static let cacheKey = "holidays.remote.v1"

    private static func remote() -> [Int: [HolidayDay]] {
        guard let raw = SharedStore.defaults.data(forKey: cacheKey),
              let dict = try? JSONDecoder().decode([String: [HolidayDay]].self, from: raw) else { return [:] }
        var out: [Int: [HolidayDay]] = [:]
        for (k, v) in dict { if let y = Int(k) { out[y] = v } }
        return out
    }

    private static var index: [String: HolidayDay] = buildIndex()

    private static func buildIndex() -> [String: HolidayDay] {
        var all = bundled
        for (y, days) in remote() where all[y] == nil { all[y] = days }
        var idx: [String: HolidayDay] = [:]
        for days in all.values { for d in days { idx[d.date] = d } }
        return idx
    }

    static func info(for date: Date, calendar: Calendar = .banli) -> HolidayDay? {
        index[DayKey.key(for: date, calendar: calendar)]
    }

    static func hasData(for year: Int) -> Bool {
        bundled[year] != nil || remote()[year] != nil
    }


    private struct RemoteFile: Decodable {
        let year: Int
        let days: [HolidayDay]
    }

    static func parse(_ data: Data) -> (year: Int, days: [HolidayDay])? {
        guard let f = try? JSONDecoder().decode(RemoteFile.self, from: data), !f.days.isEmpty else { return nil }
        return (f.year, f.days)
    }

    @MainActor
    static func refreshIfNeeded(now: Date = Date()) async {
        let year = Calendar.banli.component(.year, from: now)
        var dict = (try? JSONDecoder().decode([String: [HolidayDay]].self,
                                              from: SharedStore.defaults.data(forKey: cacheKey) ?? Data())) ?? [:]
        var changed = false
        for y in [year, year + 1] where !hasData(for: y) {
            let sources = [
                "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/\(y).json",
                "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(y).json",
            ]
            for s in sources {
                guard let url = URL(string: s),
                      let result = try? await URLSession.shared.data(from: url),
                      (result.1 as? HTTPURLResponse)?.statusCode == 200,
                      let parsed = parse(result.0), parsed.year == y else { continue }
                dict[String(y)] = parsed.days
                changed = true
                break
            }
        }
        if changed, let raw = try? JSONEncoder().encode(dict) {
            SharedStore.defaults.set(raw, forKey: cacheKey)
            index = buildIndex()
        }
    }
}

enum Lunar {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .chinese)
        c.timeZone = .current
        return c
    }()

    private static let months = [String(localized: "正"), String(localized: "二"), String(localized: "三"), String(localized: "四"), String(localized: "五"), String(localized: "六"), String(localized: "七"), String(localized: "八"), String(localized: "九"), String(localized: "十"), String(localized: "冬"), String(localized: "腊")]
    private static let days = [
        String(localized: "初一"), String(localized: "初二"), String(localized: "初三"), String(localized: "初四"), String(localized: "初五"), String(localized: "初六"), String(localized: "初七"), String(localized: "初八"), String(localized: "初九"), String(localized: "初十"),
        String(localized: "十一"), String(localized: "十二"), String(localized: "十三"), String(localized: "十四"), String(localized: "十五"), String(localized: "十六"), String(localized: "十七"), String(localized: "十八"), String(localized: "十九"), String(localized: "二十"),
        String(localized: "廿一"), String(localized: "廿二"), String(localized: "廿三"), String(localized: "廿四"), String(localized: "廿五"), String(localized: "廿六"), String(localized: "廿七"), String(localized: "廿八"), String(localized: "廿九"), String(localized: "三十"),
    ]

    static func shortText(_ date: Date) -> String {
        let c = cal.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day, (1...12).contains(m), (1...30).contains(d) else { return "" }
        if d == 1 {
            return (c.isLeapMonth == true ? String(localized: "闰") : "") + months[m - 1] + String(localized: "月")
        }
        return days[d - 1]
    }

    static func fullText(_ date: Date) -> String {
        let c = cal.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day, (1...12).contains(m), (1...30).contains(d) else { return "" }
        return String(localized: "农历") + (c.isLeapMonth == true ? String(localized: "闰") : "") + months[m - 1] + String(localized: "月") + days[d - 1]
    }
}
