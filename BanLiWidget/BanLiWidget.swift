import SwiftUI
import WidgetKit

struct ShiftEntry: TimelineEntry {
    let date: Date
    let data: ScheduleData
    let isPro: Bool
}

struct ShiftProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShiftEntry {
        ShiftEntry(date: Date(), data: ScheduleTemplate.all[0].makeData(), isPro: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ShiftEntry) -> Void) {
        completion(ShiftEntry(date: Date(), data: SharedStore.load(),
                              isPro: context.isPreview || Launch.isFree || SharedStore.isPro))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftEntry>) -> Void) {
        let cal = Calendar.banli
        let now = Date()
        let data = SharedStore.load()
        let pro = Launch.isFree || SharedStore.isPro

        var entries = [ShiftEntry(date: now, data: data, isPro: pro)]
        var day = cal.startOfDay(for: now)
        for _ in 0..<7 {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            entries.append(ShiftEntry(date: day, data: data, isPro: pro))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct ShiftWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShiftEntry

    private var cal: Calendar { .banli }
    private var today: ShiftType? { entry.data.shift(on: entry.date) }
    private var tomorrow: ShiftType? {
        cal.date(byAdding: .day, value: 1, to: entry.date).flatMap { entry.data.shift(on: $0) }
    }

    private var isHome: Bool { family == .systemSmall || family == .systemMedium }

    var body: some View {
        Group {
            if !entry.isPro {
                locked
            } else {
                switch family {
                case .systemMedium: medium
                case .accessoryCircular: circular
                case .accessoryRectangular: rectangular
                case .accessoryInline: inline
                default: small
                }
            }
        }
        .containerBackground(for: .widget) {
            if entry.isPro && isHome, let today {
                ZStack(alignment: .bottomTrailing) {
                    today.gradient
                    Image(systemName: today.symbol)
                        .font(.system(size: 90, weight: .bold))
                        .foregroundStyle(.white.opacity(0.13))
                        .offset(x: 18, y: 14)
                }
            } else {
                Color(.systemBackground)
            }
        }
    }


    @ViewBuilder private var locked: some View {
        switch family {
        case .accessoryInline:
            Text("班历：解锁后显示班次")
        case .accessoryCircular:
            Image(systemName: "lock.fill")
        default:
            VStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.title2)
                Text("打开班历解锁小组件")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }


    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("今天 · \(cal.weekdayCN(entry.date))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(today?.displayName ?? String(localized: "未设置"))
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let today {
                Text(today.isOff ? String(localized: "好好休息") : today.timeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Text("明天").font(.caption2).foregroundStyle(.white.opacity(0.8))
                Text(tomorrow?.displayName ?? "—")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.2)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            small.frame(width: 118)
            VStack(spacing: 5) {
                ForEach(1..<7, id: \.self) { i in
                    let day = cal.date(byAdding: .day, value: i, to: entry.date) ?? entry.date
                    let s = entry.data.shift(on: day)
                    HStack(spacing: 7) {
                        Text(cal.weekdayCN(day))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(minWidth: 26, alignment: .leading)
                        Text(s?.displayName ?? "—")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        if let s, !s.isOff {
                            Text(ShiftType.clock(s.startMinutes))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.16)))
                }
            }
        }
    }


    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("今天").font(.system(size: 9))
                Text(today?.shortName ?? "—").font(.system(size: 20, weight: .bold))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("今天 \(today?.displayName ?? String(localized: "未设置"))").font(.headline)
            if let today {
                Text(today.timeText).font(.caption)
            }
            Text("明天 \(tomorrow?.displayName ?? "—")").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Text("今天\(today?.displayName ?? String(localized: "未设置")) · 明天\(tomorrow?.displayName ?? "—")")
    }
}

struct ShiftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BanLiShift", provider: ShiftProvider()) { entry in
            ShiftWidgetView(entry: entry)
        }
        .configurationDisplayName("今日班次")
        .description("不用打开 App，就能看到今天和接下来几天上什么班。")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct BanLiWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShiftWidget()
        #if canImport(ActivityKit)
        ShiftLiveActivity()
        #endif
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { ShiftAlarmLiveActivity() }
        #endif
    }
}
