import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

enum ShiftActivityManager {
    static var isEnabled: Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    static func refresh(data: ScheduleData, active: Bool) async -> Bool {
        #if canImport(ActivityKit)
        let existing = Activity<ShiftActivityAttributes>.activities
        guard active, isEnabled, let shift = data.liveShift(from: Date()) else {
            for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
            return true
        }
        let state = ShiftActivityAttributes.ContentState(name: shift.type.displayName, colorHex: shift.type.colorHex,
                                                        start: shift.start, end: shift.end, isWorking: shift.isWorking)
        let content = ActivityContent(state: state, staleDate: shift.target)
        if let first = existing.first {
            await first.update(content)
            for extra in existing.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else {
            do {
                _ = try Activity.request(attributes: ShiftActivityAttributes(), content: content, pushType: nil)
            } catch { return false }
        }
        #endif
        return true
    }
}
