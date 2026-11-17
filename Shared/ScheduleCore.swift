import Foundation


extension Calendar {
    static var banli: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.locale = .current
        cal.firstWeekday = 2
        return cal
    }

    func startOfMonth(_ date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? startOfDay(for: date)
    }

    func daysBetween(_ from: Date, _ to: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: from), to: startOfDay(for: to)).day ?? 0
    }

    func weekdayCN(_ date: Date) -> String {
        shortWeekdaySymbols[component(.weekday, from: date) - 1]
    }

    func monthDayCN(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = self
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return formatter.string(from: date)
    }
}

enum DayKey {
    static func key(for date: Date, calendar: Calendar = .banli) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}


struct ShiftType: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String
    var startMinutes: Int
    var endMinutes: Int
    var isOff: Bool
    var alarms: [ShiftAlarm]

    init(id: UUID = UUID(), name: String, colorHex: String,
         startMinutes: Int = 8 * 60, endMinutes: Int = 17 * 60, isOff: Bool = false,
         alarms: [ShiftAlarm] = []) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.isOff = isOff
        self.alarms = alarms
    }

    enum CodingKeys: String, CodingKey {
        case id, name, colorHex, startMinutes, endMinutes, isOff, alarms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        startMinutes = try c.decode(Int.self, forKey: .startMinutes)
        endMinutes = try c.decode(Int.self, forKey: .endMinutes)
        isOff = try c.decode(Bool.self, forKey: .isOff)
        alarms = try c.decodeIfPresent([ShiftAlarm].self, forKey: .alarms) ?? []
    }

    var displayName: String { BuiltInNames.localized(name) }
    var shortName: String { String(displayName.prefix(1)) }

    var timeText: String {
        isOff ? String(localized: "休息") : "\(Self.clock(startMinutes))–\(Self.clock(endMinutes))"
    }

    var durationMinutes: Int {
        guard !isOff else { return 0 }
        let d = ((endMinutes - startMinutes) % 1440 + 1440) % 1440
        return d == 0 ? 1440 : d
    }

    static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}


struct CycleRun: Equatable {
    var typeID: UUID
    var count: Int
}

struct ScheduleData: Codable, Equatable {
    var types: [ShiftType]
    var cycle: [UUID]
    var cycleStart: Date
    var overrides: [String: UUID]
    var reminderEnabled: Bool
    var reminderMinutesBefore: Int
    var templateName: String
    var notes: [String: String] = [:]
    var eveningReminderEnabled = false
    var eveningReminderMinutes = 21 * 60
    var remindOnOffDays = true
    var alarmDelivery: AlarmDelivery = .alarm
    var liveActivityEnabled = false
    var customID: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case types, cycle, cycleStart, overrides, reminderEnabled, reminderMinutesBefore, templateName, notes
        case eveningReminderEnabled, eveningReminderMinutes, remindOnOffDays, alarmDelivery, liveActivityEnabled
        case customID
    }

    init(types: [ShiftType], cycle: [UUID], cycleStart: Date, overrides: [String: UUID],
         reminderEnabled: Bool, reminderMinutesBefore: Int, templateName: String,
         notes: [String: String] = [:]) {
        self.types = types
        self.cycle = cycle
        self.cycleStart = cycleStart
        self.overrides = overrides
        self.reminderEnabled = reminderEnabled
        self.reminderMinutesBefore = reminderMinutesBefore
        self.templateName = templateName
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        types = try c.decode([ShiftType].self, forKey: .types)
        cycle = try c.decode([UUID].self, forKey: .cycle)
        cycleStart = try c.decode(Date.self, forKey: .cycleStart)
        overrides = try c.decodeIfPresent([String: UUID].self, forKey: .overrides) ?? [:]
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderMinutesBefore = try c.decodeIfPresent(Int.self, forKey: .reminderMinutesBefore) ?? 60
        templateName = try c.decodeIfPresent(String.self, forKey: .templateName) ?? String(localized: "自定义")
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
        eveningReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .eveningReminderEnabled) ?? false
        eveningReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .eveningReminderMinutes) ?? 21 * 60
        remindOnOffDays = try c.decodeIfPresent(Bool.self, forKey: .remindOnOffDays) ?? true
        alarmDelivery = try c.decodeIfPresent(AlarmDelivery.self, forKey: .alarmDelivery) ?? .alarm
        liveActivityEnabled = try c.decodeIfPresent(Bool.self, forKey: .liveActivityEnabled) ?? false
        customID = try c.decodeIfPresent(UUID.self, forKey: .customID)
    }

    var displayTemplateName: String { BuiltInNames.localized(templateName) }

    func type(id: UUID) -> ShiftType? { types.first { $0.id == id } }

    func note(on date: Date, calendar: Calendar = .banli) -> String? {
        let n = notes[DayKey.key(for: date, calendar: calendar)]
        return (n?.isEmpty ?? true) ? nil : n
    }

    mutating func setNote(_ text: String, on date: Date, calendar: Calendar = .banli) {
        let key = DayKey.key(for: date, calendar: calendar)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { notes.removeValue(forKey: key) } else { notes[key] = t }
    }

    func monthWorkMinutes(for month: Date, calendar: Calendar = .banli) -> Int {
        let start = calendar.startOfMonth(month)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return 0 }
        var total = 0
        for d in 0..<range.count {
            guard let day = calendar.date(byAdding: .day, value: d, to: start) else { continue }
            total += shift(on: day, calendar: calendar)?.durationMinutes ?? 0
        }
        return total
    }

    func shiftInterval(on date: Date, calendar: Calendar = .banli) -> (start: Date, end: Date)? {
        guard let t = shift(on: date, calendar: calendar), !t.isOff,
              let start = Self.clockDate(minutes: t.startMinutes, on: date, calendar: calendar) else { return nil }
        let nextDay = t.endMinutes <= t.startMinutes || t.endMinutes == 1440
        guard let endDay = calendar.date(byAdding: .day, value: nextDay ? 1 : 0, to: date),
              let end = Self.clockDate(minutes: t.endMinutes % 1440, on: endDay, calendar: calendar) else { return nil }
        return (start, end)
    }

    func cycleIndex(on date: Date, calendar: Calendar = .banli) -> Int? {
        guard !cycle.isEmpty else { return nil }
        let n = calendar.daysBetween(cycleStart, date)
        return ((n % cycle.count) + cycle.count) % cycle.count
    }

    func cycleShift(on date: Date, calendar: Calendar = .banli) -> ShiftType? {
        guard let i = cycleIndex(on: date, calendar: calendar) else { return nil }
        return type(id: cycle[i])
    }

    func shift(on date: Date, calendar: Calendar = .banli) -> ShiftType? {
        if let o = overrides[DayKey.key(for: date, calendar: calendar)], let t = type(id: o) {
            return t
        }
        return cycleShift(on: date, calendar: calendar)
    }

    func isOverridden(_ date: Date, calendar: Calendar = .banli) -> Bool {
        guard let o = overrides[DayKey.key(for: date, calendar: calendar)] else { return false }
        return type(id: o) != nil
    }

    mutating func setShift(_ typeID: UUID?, on date: Date, calendar: Calendar = .banli) {
        let key = DayKey.key(for: date, calendar: calendar)
        if let typeID, typeID != cycleShift(on: date, calendar: calendar)?.id {
            overrides[key] = typeID
        } else {
            overrides.removeValue(forKey: key)
        }
    }

    mutating func setToday(isCycleDay index: Int, today: Date = Date(), calendar: Calendar = .banli) {
        let start = calendar.startOfDay(for: today)
        cycleStart = calendar.date(byAdding: .day, value: -index, to: start) ?? start
    }

    var cycleRuns: [CycleRun] {
        get { CycleRun.runs(of: cycle) }
        set {
            guard !newValue.isEmpty else { return }
            cycle = CycleRun.expand(newValue)
        }
    }

    mutating func removeType(id: UUID) {
        types.removeAll { $0.id == id }
        cycle.removeAll { $0 == id }
        overrides = overrides.filter { $0.value != id }
        if cycle.isEmpty, let remaining = types.first { cycle = [remaining.id] }
    }

    func monthStats(for month: Date, calendar: Calendar = .banli) -> [(type: ShiftType, days: Int)] {
        let start = calendar.startOfMonth(month)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        var counts: [UUID: Int] = [:]
        for d in 0..<range.count {
            guard let day = calendar.date(byAdding: .day, value: d, to: start),
                  let t = shift(on: day, calendar: calendar) else { continue }
            counts[t.id, default: 0] += 1
        }
        var result: [(type: ShiftType, days: Int)] = []
        for t in types {
            if let n = counts[t.id] { result.append((type: t, days: n)) }
        }
        return result
    }

    struct Reminder: Equatable {
        let fireDate: Date
        let shiftStart: Date
        let type: ShiftType
    }

    func upcomingReminders(from now: Date, days: Int = 60, limit: Int = 60,
                           calendar: Calendar = .banli) -> [Reminder] {
        guard days >= 0, limit > 0 else { return [] }
        var result: [Reminder] = []
        let today = calendar.startOfDay(for: now)
        for d in 0...days {
            guard let day = calendar.date(byAdding: .day, value: d, to: today),
                  let t = shift(on: day, calendar: calendar), !t.isOff,
                  let start = Self.clockDate(minutes: t.startMinutes, on: day, calendar: calendar),
                  let fire = calendar.date(byAdding: .minute, value: -reminderMinutesBefore, to: start),
                  fire > now else { continue }
            result.append(Reminder(fireDate: fire, shiftStart: start, type: t))
            if result.count >= limit { break }
        }
        return result
    }
}


struct ScheduleTemplate: Identifiable {
    struct Kind {
        let name: String
        let colorHex: String
        let start: Int
        let end: Int
        let isOff: Bool
    }

    let id: String
    let name: String
    let detail: String
    let kinds: [Kind]
    let pattern: [Int]

    var patternNames: [String] { pattern.map { kinds[$0].name } }

    func makeData(today: Date = Date(), calendar: Calendar = .banli) -> ScheduleData {
        let types = kinds.map {
            ShiftType(name: $0.name, colorHex: $0.colorHex,
                      startMinutes: $0.start, endMinutes: $0.end, isOff: $0.isOff)
        }
        return ScheduleData(
            types: types,
            cycle: pattern.map { types[$0].id },
            cycleStart: calendar.startOfDay(for: today),
            overrides: [:],
            reminderEnabled: false,
            reminderMinutesBefore: 60,
            templateName: name
        )
    }

    private static let white = Kind(name: String(localized: "白班"), colorHex: "F2994A", start: 8 * 60, end: 20 * 60, isOff: false)
    private static let night12 = Kind(name: String(localized: "夜班"), colorHex: "5B5FC7", start: 20 * 60, end: 8 * 60, isOff: false)
    private static let early = Kind(name: String(localized: "早班"), colorHex: "F2994A", start: 8 * 60, end: 16 * 60, isOff: false)
    private static let middle = Kind(name: String(localized: "中班"), colorHex: "2D9CDB", start: 16 * 60, end: 24 * 60, isOff: false)
    private static let night8 = Kind(name: String(localized: "夜班"), colorHex: "5B5FC7", start: 0, end: 8 * 60, isOff: false)
    private static let day9 = Kind(name: String(localized: "白班"), colorHex: "27AE60", start: 9 * 60, end: 18 * 60, isOff: false)
    private static let off = Kind(name: String(localized: "休息"), colorHex: "9AA0A6", start: 0, end: 0, isOff: true)

    static let all: [ScheduleTemplate] = [
        ScheduleTemplate(id: "bysx", name: String(localized: "两班倒（白夜休休）"), detail: String(localized: "12 小时班，4 天一循环"),
                         kinds: [white, night12, off], pattern: [0, 1, 2, 2]),
        ScheduleTemplate(id: "4b3d", name: String(localized: "四班三倒"), detail: String(localized: "早早中中夜夜休休，8 天一循环"),
                         kinds: [early, middle, night8, off], pattern: [0, 0, 1, 1, 2, 2, 3, 3]),
        ScheduleTemplate(id: "zzyx", name: String(localized: "三班倒（早中夜休）"), detail: String(localized: "8 小时班，4 天一循环"),
                         kinds: [early, middle, night8, off], pattern: [0, 1, 2, 3]),
        ScheduleTemplate(id: "z1x1", name: String(localized: "做一休一"), detail: String(localized: "上一天休一天"),
                         kinds: [white, off], pattern: [0, 1]),
        ScheduleTemplate(id: "s2x2", name: String(localized: "上二休二"), detail: String(localized: "上两天休两天"),
                         kinds: [day9, off], pattern: [0, 0, 1, 1]),
        ScheduleTemplate(id: "z6x1", name: String(localized: "做六休一"), detail: String(localized: "一周休一天"),
                         kinds: [day9, off], pattern: [0, 0, 0, 0, 0, 0, 1]),
        ScheduleTemplate(id: "custom", name: String(localized: "自定义"), detail: String(localized: "自己排：什么班、上几天、休几天"),
                         kinds: [day9, off], pattern: [0, 1]),
    ]
}
