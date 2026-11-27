import Foundation

struct ShiftAlarm: Codable, Identifiable, Hashable {
    var id = UUID()
    var minutes = 6 * 60
    var dayBefore = false
    var enabled = true
}

enum AlarmDelivery: String, Codable, CaseIterable {
    case alarm, notification
}

extension ScheduleData {
    struct PlannedNotification: Equatable, Identifiable {
        enum Kind: String { case beforeShift, evening, shiftAlarm }
        let id: String
        let kind: Kind
        let fireDate: Date
        let type: ShiftType
    }

    struct PlannedAlarm: Equatable, Identifiable {
        let id: String
        let fireDate: Date
        let shiftStart: Date
        let type: ShiftType
    }

    static func clockDate(minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        let m = min(max(minutes, 0), 1439)
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    func plannedAlarms(from now: Date, days: Int = 14, limit: Int = 60,
                       calendar: Calendar = .banli) -> [PlannedAlarm] {
        guard days > 0, limit > 0,
              let end = calendar.date(byAdding: .day, value: days, to: now) else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [PlannedAlarm] = []
        for offset in 0...(days + 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let type = shift(on: day, calendar: calendar), !type.isOff,
                  let start = Self.clockDate(minutes: type.startMinutes, on: day, calendar: calendar) else { continue }
            for alarm in type.alarms where alarm.enabled {
                let alarmDay = calendar.date(byAdding: .day, value: alarm.dayBefore ? -1 : 0, to: day) ?? day
                guard let fire = Self.clockDate(minutes: alarm.minutes, on: alarmDay, calendar: calendar),
                      fire > now, fire <= end, fire <= start else { continue }
                let id = "alarm-\(DayKey.key(for: day, calendar: calendar))-\(type.id)-\(alarm.id)"
                result.append(PlannedAlarm(id: id, fireDate: fire, shiftStart: start, type: type))
            }
        }
        return Array(result.sorted {
            $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate
        }.prefix(min(limit, 60)))
    }

    func plannedNotifications(from now: Date, includeShiftAlarms: Bool,
                              days: Int = 120, limit: Int = 60,
                              calendar: Calendar = .banli) -> [PlannedNotification] {
        guard days >= 0, limit > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [PlannedNotification] = []
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let type = shift(on: day, calendar: calendar) else { continue }
            let key = DayKey.key(for: day, calendar: calendar)
            if reminderEnabled, !type.isOff,
               let start = Self.clockDate(minutes: type.startMinutes, on: day, calendar: calendar),
               let fire = calendar.date(byAdding: .minute, value: -min(max(reminderMinutesBefore, 0), 120), to: start),
               fire > now {
                result.append(PlannedNotification(id: "before-\(key)", kind: .beforeShift, fireDate: fire, type: type))
            }
            if eveningReminderEnabled, !type.isOff || remindOnOffDays,
               let previous = calendar.date(byAdding: .day, value: -1, to: day),
               let fire = Self.clockDate(minutes: eveningReminderMinutes, on: previous, calendar: calendar), fire > now {
                result.append(PlannedNotification(id: "evening-\(key)", kind: .evening, fireDate: fire, type: type))
            }
        }
        if includeShiftAlarms {
            result += plannedAlarms(from: now, days: max(1, days), limit: 60, calendar: calendar).map {
                PlannedNotification(id: $0.id, kind: .shiftAlarm, fireDate: $0.fireDate, type: $0.type)
            }
        }
        return Array(result.sorted {
            $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate
        }.prefix(min(limit, 60)))
    }

    struct LiveShift: Equatable {
        let type: ShiftType
        let start: Date
        let end: Date
        let isWorking: Bool
        var target: Date { isWorking ? end : start }
    }

    func liveShift(from now: Date, calendar: Calendar = .banli) -> LiveShift? {
        let today = calendar.startOfDay(for: now)
        var next: LiveShift?
        let horizon = max(400, cycle.count + 1)
        for offset in -1...horizon {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let type = shift(on: day, calendar: calendar), !type.isOff,
                  let interval = shiftInterval(on: day, calendar: calendar), interval.end > now else { continue }
            let working = interval.start <= now
            let item = LiveShift(type: type, start: interval.start, end: interval.end, isWorking: working)
            if working { return item }
            if next == nil { next = item }
            if next != nil && offset >= 1 { break }
        }
        return next
    }

    mutating func copyReminderSettings(from old: ScheduleData) {
        reminderEnabled = old.reminderEnabled
        reminderMinutesBefore = old.reminderMinutesBefore
        eveningReminderEnabled = old.eveningReminderEnabled
        eveningReminderMinutes = old.eveningReminderMinutes
        remindOnOffDays = old.remindOnOffDays
        alarmDelivery = old.alarmDelivery
        liveActivityEnabled = old.liveActivityEnabled
    }
}
