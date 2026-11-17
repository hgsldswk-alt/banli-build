import Foundation

struct CustomSchedule: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var types: [ShiftType]
    var cycle: [UUID]
    var cycleStart: Date?

    init(id: UUID = UUID(), name: String, types: [ShiftType], cycle: [UUID], cycleStart: Date? = nil) {
        self.id = id
        self.name = name
        self.types = types
        self.cycle = cycle
        self.cycleStart = cycleStart
    }

    func todayIndex(now: Date = Date(), calendar: Calendar = .banli) -> Int {
        guard let start = cycleStart, !cycle.isEmpty else { return 0 }
        let n = calendar.daysBetween(start, now)
        return ((n % cycle.count) + cycle.count) % cycle.count
    }

    static func from(_ t: ScheduleTemplate) -> CustomSchedule {
        let d = t.makeData()
        return CustomSchedule(name: t.name, types: d.types, cycle: d.cycle)
    }

    var runs: [CycleRun] {
        get { CycleRun.runs(of: cycle) }
        set {
            guard !newValue.isEmpty else { return }
            cycle = CycleRun.expand(newValue)
        }
    }

    func type(id: UUID) -> ShiftType? { types.first { $0.id == id } }

    static func blank(name: String) -> CustomSchedule {
        let work = ShiftType(name: String(localized: "白班"), colorHex: "27AE60",
                             startMinutes: 8 * 60, endMinutes: 17 * 60)
        let off = ShiftType(name: String(localized: "休息"), colorHex: "9AA0A6",
                            startMinutes: 0, endMinutes: 0, isOff: true)
        return CustomSchedule(name: name, types: [work, off],
                              cycle: [work.id, work.id, work.id, off.id, off.id])
    }

    mutating func removeType(id: UUID) {
        guard types.count > 1 else { return }
        types.removeAll { $0.id == id }
        cycle.removeAll { $0 == id }
        if cycle.isEmpty, let first = types.first { cycle = [first.id] }
    }

    static func defaultName(existing: [CustomSchedule]) -> String {
        let base = String(localized: "我的排班")
        let names = Set(existing.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

extension CycleRun {
    static func runs(of cycle: [UUID]) -> [CycleRun] {
        var runs: [CycleRun] = []
        for id in cycle {
            if let last = runs.last, last.typeID == id {
                runs[runs.count - 1].count += 1
            } else {
                runs.append(CycleRun(typeID: id, count: 1))
            }
        }
        return runs
    }

    static func expand(_ runs: [CycleRun]) -> [UUID] {
        runs.flatMap { Array(repeating: $0.typeID, count: max(1, $0.count)) }
    }
}
