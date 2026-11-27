#if canImport(AlarmKit) && canImport(AppIntents)
import AlarmKit
import AppIntents
import Foundation

@available(iOS 26.0, *)
struct StopShiftAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止闹钟"
    @Parameter(title: "闹钟标识") var alarmID: String

    init() { alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.stop(id: id) }
        return .result()
    }
}
#endif
