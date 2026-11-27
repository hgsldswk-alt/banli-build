import Foundation
import UserNotifications

enum ReminderScheduler {
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(data: ScheduleData, active: Bool, includeShiftAlarms: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard active else { return true }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional ||
                settings.authorizationStatus == .ephemeral else { return true }

        let cal = Calendar.banli
        var succeeded = true
        for item in data.plannedNotifications(from: Date(), includeShiftAlarms: includeShiftAlarms) {
            let content = UNMutableNotificationContent()
            switch item.kind {
            case .beforeShift:
                content.title = String(localized: "\(item.type.displayName)快到了")
                let lead = min(max(data.reminderMinutesBefore, 0), 120)
                content.body = lead > 0
                    ? String(localized: "\(ShiftType.clock(item.type.startMinutes)) 上班，还有 \(lead) 分钟")
                    : String(localized: "\(ShiftType.clock(item.type.startMinutes)) 上班")
            case .evening:
                content.title = item.type.isOff ? String(localized: "明天休息")
                    : String(localized: "明天：\(item.type.displayName)")
                content.body = item.type.isOff ? String(localized: "好好休息") : item.type.timeText
            case .shiftAlarm:
                content.title = String(localized: "班次闹钟：\(item.type.displayName)")
                content.body = item.type.timeText
            }
            content.sound = .default
            content.interruptionLevel = .active

            var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            comps.timeZone = cal.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            } catch { succeeded = false }
        }
        return succeeded
    }
}
