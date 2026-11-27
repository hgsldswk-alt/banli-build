#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct ShiftActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var name: String
        var colorHex: String
        var start: Date
        var end: Date
        var isWorking: Bool
        var target: Date { isWorking ? end : start }
    }
}
#endif

#if canImport(AlarmKit)
import AlarmKit

@available(iOS 26.0, *)
struct ShiftAlarmMetadata: AlarmMetadata {
    var name: String
}
#endif
