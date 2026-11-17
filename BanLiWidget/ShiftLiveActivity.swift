#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

struct ShiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(Color(hex: context.state.colorHex))
                    Text(context.state.name).font(.headline).lineLimit(1)
                    Spacer()
                    Text(context.state.isWorking ? String(localized: "正在上班") : String(localized: "下一个班")).font(.caption)
                }
                HStack {
                    interval(context.state)
                    Spacer()
                    if context.isStale {
                        staleText(context.state).font(.subheadline.weight(.semibold))
                    } else {
                        VStack(alignment: .trailing) {
                            Text(context.state.isWorking ? String(localized: "距下班") : String(localized: "距上班")).font(.caption)
                            countdown(context.state).font(.title2.monospacedDigit())
                        }
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color(.secondarySystemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.name, systemImage: "calendar")
                        .foregroundStyle(Color(hex: context.state.colorHex)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isWorking ? String(localized: "距下班") : String(localized: "距上班")).font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        interval(context.state)
                        Spacer()
                        if context.isStale { staleText(context.state) }
                        else { countdown(context.state).monospacedDigit() }
                    }
                    .font(.subheadline)
                }
            } compactLeading: {
                Text(String(context.state.name.prefix(1))).foregroundStyle(Color(hex: context.state.colorHex))
            } compactTrailing: {
                if context.isStale { Image(systemName: "arrow.clockwise") }
                else { countdown(context.state).monospacedDigit().frame(maxWidth: 64) }
            } minimal: {
                Image(systemName: "calendar.badge.clock").foregroundStyle(Color(hex: context.state.colorHex))
            }
        }
    }

    private func interval(_ state: ShiftActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.start, format: .dateTime.month().day())
            HStack(spacing: 2) {
                Text(state.start, style: .time)
                Text("–")
                Text(state.end, style: .time)
            }
        }
        .font(.caption)
    }

    private func staleText(_ state: ShiftActivityAttributes.ContentState) -> Text {
        if state.isWorking {
            return Text("已下班")
        }
        return Text("上班中 · \(state.end.formatted(date: .omitted, time: .shortened)) 下班")
    }

    private func countdown(_ state: ShiftActivityAttributes.ContentState) -> some View {
        Text(timerInterval: min(Date(), state.target)...state.target, countsDown: true)
    }
}
#endif

#if canImport(AlarmKit)
import AlarmKit

@available(iOS 26.0, *)
struct ShiftAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ShiftAlarmMetadata>.self) { context in
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.attributes.metadata?.name ?? String(localized: "班次闹钟")).font(.headline)
                    alarmCountdown(context.state)
                }
                Spacer()
                Button(intent: StopShiftAlarmIntent(alarmID: context.state.alarmID.uuidString)) {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.metadata?.name ?? String(localized: "班次闹钟"))
                }
                DynamicIslandExpandedRegion(.trailing) { alarmCountdown(context.state) }
                DynamicIslandExpandedRegion(.bottom) {
                    Button(intent: StopShiftAlarmIntent(alarmID: context.state.alarmID.uuidString)) {
                        Label("停止", systemImage: "stop.fill")
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
            } compactTrailing: {
                alarmCountdown(context.state).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "alarm.fill")
            }
        }
    }

    @ViewBuilder private func alarmCountdown(_ state: AlarmPresentationState) -> some View {
        if case .countdown(let countdown) = state.mode {
            Text(timerInterval: min(Date(), countdown.fireDate)...countdown.fireDate, countsDown: true)
                .monospacedDigit()
        } else { Text("班次闹钟") }
    }
}
#endif
