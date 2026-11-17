import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

enum ShiftAlarmScheduler {
    static var isAvailable: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    static var isDenied: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .denied }
        #endif
        return false
    }

    static var isAuthorized: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .authorized }
        #endif
        return false
    }

    static var needsPermission: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .notDetermined }
        #endif
        return false
    }

    static func requestPermission() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
        }
        #endif
        return false
    }

    static func reschedule(data: ScheduleData, active: Bool) async -> String? {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            guard manager.authorizationState == .authorized else { return nil }
            do {
                for alarm in try manager.alarms { try manager.cancel(id: alarm.id) }
            } catch { return String(localized: "旧闹钟未能全部清除，新的排班尚未生效。请重试。") }
            guard active, data.alarmDelivery == .alarm else { return nil }
            for item in data.plannedAlarms(from: Date()) {
                let alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource("班次闹钟：\(item.type.displayName)"),
                    stopButton: AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill"),
                    secondaryButton: AlarmButton(text: "稍后提醒", textColor: .white, systemImageName: "zzz"),
                    secondaryButtonBehavior: .countdown)
                let countdown = AlarmPresentation.Countdown(title: "稍后提醒", pauseButton: nil)
                let attributes = AlarmAttributes<ShiftAlarmMetadata>(
                    presentation: AlarmPresentation(alert: alert, countdown: countdown),
                    metadata: ShiftAlarmMetadata(name: item.type.displayName), tintColor: Color(hex: item.type.colorHex))
                let configuration = AlarmManager.AlarmConfiguration<ShiftAlarmMetadata>(
                    countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: 9 * 60),
                    schedule: .fixed(item.fireDate), attributes: attributes, sound: .default)
                do {
                    _ = try await manager.schedule(id: UUID(), configuration: configuration)
                } catch {
                    return String(localized: "部分闹钟未能排入系统，成功排入的闹钟会保留。请减少闹钟数量后重试。")
                }
            }
        }
        #endif
        return nil
    }
}
