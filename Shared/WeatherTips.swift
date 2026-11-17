import Foundation


struct WeatherSnapshot: Codable, Equatable {
    struct Hour: Codable, Equatable {
        let date: Date
        let temperature: Double
        let precipitationChance: Double
        let symbol: String
        let condition: String
    }

    struct Day: Codable, Equatable {
        let date: Date
        let high: Double
        let low: Double
        let precipitationChance: Double
        let symbol: String
        let condition: String
    }

    var hours: [Hour]
    var days: [Day]
    var fetchedAt: Date
    var place: String?
    var markLightURL: URL?
    var markDarkURL: URL?
    var legalURL: URL?
    var language: String? = nil

    func hour(near date: Date) -> Hour? {
        let best = hours.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        guard let best, abs(best.date.timeIntervalSince(date)) <= 90 * 60 else { return nil }
        return best
    }

    func day(for date: Date, calendar: Calendar = .banli) -> Day? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func isFresh(now: Date = Date(), maxAge: TimeInterval = 3600) -> Bool {
        now.timeIntervalSince(fetchedAt) < maxAge
    }
}

enum WeatherCache {
    private static let key = "weather.snapshot.v1"
    private static let enabledKey = "weather.enabled"

    static func load() -> WeatherSnapshot? {
        guard let raw = SharedStore.defaults.data(forKey: key) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: raw),
              snapshot.language == Locale.preferredLanguages.first else { return nil }
        return snapshot
    }

    static func save(_ snap: WeatherSnapshot) {
        var snapshot = snap
        snapshot.language = Locale.preferredLanguages.first
        if let raw = try? JSONEncoder().encode(snapshot) { SharedStore.defaults.set(raw, forKey: key) }
    }

    static var enabled: Bool {
        get { SharedStore.defaults.bool(forKey: enabledKey) }
        set { SharedStore.defaults.set(newValue, forKey: enabledKey) }
    }
}


struct DailyTip: Identifiable, Equatable {
    let id: String
    let symbol: String
    let text: String
}

enum TipEngine {
    static func tips(data: ScheduleData, now: Date, weather: WeatherSnapshot?,
                     calendar: Calendar = .banli,
                     features: LocaleFeatures = .current) -> [DailyTip] {
        var out: [DailyTip] = []
        func add(_ id: String, _ symbol: String, _ text: String) {
            if out.count < 3, !out.contains(where: { $0.id == id }) {
                out.append(DailyTip(id: id, symbol: symbol, text: text))
            }
        }

        let today = data.shift(on: now, calendar: calendar)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let yesterday = data.shift(on: yesterdayDate, calendar: calendar)
        let tomorrow = data.shift(on: tomorrowDate, calendar: calendar)
        let usableWeather = weather.flatMap { $0.isFresh(now: now, maxAge: 6 * 3600) ? $0 : nil }

        if let w = usableWeather, let iv = data.shiftInterval(on: now, calendar: calendar), now < iv.end {
            let legs: [(String, Date)] = now < iv.start ? [(String(localized: "上班"), iv.start), (String(localized: "下班"), iv.end)] : [(String(localized: "下班"), iv.end)]
            for (leg, time) in legs {
                guard let h = w.hour(near: time) else { continue }
                let clock = ShiftType.clock(calendar.component(.hour, from: time) * 60 + calendar.component(.minute, from: time))
                if h.precipitationChance >= 0.5 {
                    add("rain", "umbrella.fill", String(localized: "\(leg)时（\(clock)）可能下雨，记得带伞"))
                }
                if h.temperature <= 5 {
                    add("cold", "thermometer.snowflake", String(localized: "\(leg)时只有 \(Int(h.temperature.rounded()))°C，多穿一件"))
                } else if h.temperature >= 33 {
                    add("hot", "sun.max.trianglebadge.exclamationmark", String(localized: "\(leg)路上 \(Int(h.temperature.rounded()))°C，注意防暑多喝水"))
                }
            }
        }

        if features.showsChinaHolidays, let h = Holidays.info(for: now, calendar: calendar) {
            if h.isOffDay, let today, !today.isOff {
                add("holiday", "gift.fill", String(localized: "今天是\(h.displayName)假期，还在上班的你辛苦了"))
            } else if !h.isOffDay {
                add("makeup", "briefcase.fill", String(localized: "今天是\(h.displayName)调休上班日"))
            }
        }

        if let today {
            let isNight = !today.isOff && (today.startMinutes >= 18 * 60 || today.startMinutes < 6 * 60)
            if isNight {
                add("night", "moon.zzz.fill", String(localized: "今晚\(today.displayName)，白天抓紧补觉，备点夜宵"))
            } else if today.isOff {
                if let y = yesterday, !y.isOff, y.startMinutes >= 18 * 60 {
                    add("afterNight", "bed.double.fill", String(localized: "夜班刚结束，今天好好补一觉"))
                } else if let d = usableWeather?.day(for: now, calendar: calendar) {
                    add("offDay", "figure.walk",
                        d.precipitationChance >= 0.5 ? String(localized: "今天休息，外面可能下雨，在家歇着吧") : String(localized: "今天休息，天气不错，出门走走"))
                } else {
                    add("offDay", "cup.and.saucer.fill", String(localized: "今天休息，好好放松一下"))
                }
            }
        }
        if let tomorrow, !tomorrow.isOff, tomorrow.startMinutes < 8 * 60, tomorrow.startMinutes >= 4 * 60 {
            add("earlyTomorrow", "alarm.fill", String(localized: "明天 \(ShiftType.clock(tomorrow.startMinutes)) 上班，今晚早点睡"))
        }

        if let d = usableWeather?.day(for: now, calendar: calendar) {
            add("today", d.symbol, String(localized: "今天\(d.condition)，\(Int(d.low.rounded()))°C～\(Int(d.high.rounded()))°C"))
        }

        if out.isEmpty {
            add("care", "heart.fill", String(localized: "按时吃饭，照顾好自己"))
        }
        return out
    }
}
