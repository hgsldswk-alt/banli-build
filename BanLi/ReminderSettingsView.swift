import SwiftUI
import UIKit

struct ReminderSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false

    var body: some View {
        @Bindable var model = model
        Form {
            if !model.isPro {
                Section {
                    Button("解锁高级版") { showPaywall = true }
                    Text("上班提醒、班次闹钟和锁屏实时显示属于高级版。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ReminderPermissionRows()
            Section {
                Toggle("上班前提醒", isOn: $model.data.reminderEnabled)
                    .onChange(of: model.data.reminderEnabled) { _, on in
                        if on { Task { await model.authorizeNotifications() } }
                    }
                if model.data.reminderEnabled {
                    Picker("提前多久提醒", selection: $model.data.reminderMinutesBefore) {
                        ForEach([0, 15, 30, 45, 60, 90, 120], id: \.self) { m in
                            Text(m == 0 ? String(localized: "准点") : String(localized: "\(m) 分钟")).tag(m)
                        }
                    }
                }
            } header: { Text("上班前提醒") }
            .disabled(!model.isPro)

            Section {
                Toggle("前一晚提醒明天的班", isOn: $model.data.eveningReminderEnabled)
                    .onChange(of: model.data.eveningReminderEnabled) { _, on in
                        if on { Task { await model.authorizeNotifications() } }
                    }
                if model.data.eveningReminderEnabled {
                    DatePicker("提醒时间", selection: reminderClockBinding($model.data.eveningReminderMinutes),
                               displayedComponents: .hourAndMinute)
                    Toggle("明天休息也提醒", isOn: $model.data.remindOnOffDays)
                }
            } header: { Text("前一晚提醒") } footer: {
                Text("按班次开始日的前一天提醒，夜班和跨夜班也一样。")
            }
            .disabled(!model.isPro)

            Section {
                if ShiftAlarmScheduler.isAvailable {
                    Picker("响铃方式", selection: $model.data.alarmDelivery) {
                        Text("闹钟（静音也会响）").tag(AlarmDelivery.alarm)
                        Text("普通通知").tag(AlarmDelivery.notification)
                    }
                    .disabled(!model.isPro)
                    .onChange(of: model.data.alarmDelivery) { _, _ in
                        Task { await model.authorizeShiftAlarms() }
                    }
                } else {
                    LabeledContent("响铃方式", value: String(localized: "普通通知"))
                    Text("把 iPhone 升级到 iOS 26 后，可以改用静音也会响的闹钟。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(model.data.types.filter { !$0.isOff }) { type in
                    NavigationLink { ShiftAlarmsView(typeID: type.id) } label: {
                        HStack(spacing: 12) {
                            ShiftChip(type: type, size: 28)
                            VStack(alignment: .leading) {
                                Text(type.displayName)
                                Text(type.timeText).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(alarmSummary(type))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } header: { Text("按班次设置闹钟") } footer: {
                Text("每个班可以设多个闹钟，比如早班 6:00、6:10。调班后自动按新班次响，休息日不响。")
            }

            Section {
                Toggle("锁屏实时显示", isOn: $model.data.liveActivityEnabled)
                    .disabled(!model.isPro)
                if model.data.liveActivityEnabled && !model.activitiesAllowed {
                    Text("实时活动已关闭，请在系统设置中打开。")
                        .foregroundStyle(.secondary)
                    Button("去设置打开") { openBanLiSettings() }
                }
                if model.data.liveActivityEnabled && model.data.liveShift(from: Date()) == nil {
                    Text("没有可显示的工作班次，请先设置排班。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                NavigationLink("桌面和锁屏小组件") { WidgetGuideView() }
            } header: { Text("锁屏实时显示") } footer: {
                Text("在锁屏和灵动岛显示下一个班的倒计时，上班中显示离下班还有多久。每次打开班历会刷新一次，系统最多显示约 8 小时；想一直显示，请添加锁屏小组件。")
            }

            Section {
                Text("普通通知在静音或专注模式下可能没有声音；闹钟静音也会响，可以稍后再响（9 分钟）。")
                Text("提醒会提前排好几周，每次打开班历自动往后续排。两三周没打开过的话，打开一下就行。")
            }
            .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("提醒设置")
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .task { await model.refreshReminderPermissions() }
    }
}

struct ShiftAlarmsView: View {
    @Environment(AppModel.self) private var model
    let typeID: UUID
    @State private var showPaywall = false

    var body: some View {
        Form {
            if let type = model.data.type(id: typeID), !type.isOff {
                Section {
                    HStack(spacing: 12) {
                        ShiftChip(type: type)
                        VStack(alignment: .leading) {
                            Text(type.displayName).font(.headline)
                            Text(type.timeText).foregroundStyle(.secondary)
                        }
                    }
                }
                if !model.isPro {
                    Section { Button("解锁高级版") { showPaywall = true } }
                }
                ReminderPermissionRows()

                Section {
                    ForEach(type.alarms) { alarm in
                        ShiftAlarmRow(alarm: alarmBinding(alarm), startMinutes: type.startMinutes)
                    }
                    .onDelete { offsets in
                        guard model.isPro, var changed = model.data.type(id: typeID) else { return }
                        changed.alarms.remove(atOffsets: offsets)
                        model.updateType(changed)
                    }
                    .disabled(!model.isPro)

                    Button {
                        guard model.isPro else { showPaywall = true; return }
                        var changed = type
                        let base = type.alarms.last.map { $0.minutes + 10 } ?? (type.startMinutes - 60)
                        let wrapped = (base % 1440 + 1440) % 1440
                        let dayBefore = type.alarms.last?.dayBefore ?? (type.startMinutes < 60)
                        changed.alarms.append(ShiftAlarm(minutes: wrapped, dayBefore: dayBefore))
                        model.updateType(changed)
                        Task { await model.authorizeShiftAlarms() }
                    } label: { Label("添加闹钟", systemImage: "plus.circle") }
                } header: {
                    Text("闹钟")
                } footer: {
                    Text("可以加多个，比如 6:00、6:10。夜班想提前一天响，就把「当天」改成「前一天」。左滑删除。")
                }

                Section {
                    NavigationLink("响铃方式与其他提醒") { ReminderSettingsView() }
                }
            } else {
                Text("休息日不能设置闹钟，或这个班次已删除。")
            }
        }
        .navigationTitle("这个班的闹钟")
        .toolbar { EditButton() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .task { await model.refreshReminderPermissions() }
    }

    private func alarmBinding(_ original: ShiftAlarm) -> Binding<ShiftAlarm> {
        Binding(get: {
            model.data.type(id: typeID)?.alarms.first { $0.id == original.id } ?? original
        }, set: { value in
            guard model.isPro, var type = model.data.type(id: typeID), !type.isOff,
                  let index = type.alarms.firstIndex(where: { $0.id == original.id }) else { return }
            let wasEnabled = type.alarms[index].enabled
            type.alarms[index] = value
            model.updateType(type)
            if value.enabled && !wasEnabled { Task { await model.authorizeShiftAlarms() } }
        })
    }
}

private struct ShiftAlarmRow: View {
    @Binding var alarm: ShiftAlarm
    let startMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                DatePicker("响铃时间", selection: reminderClockBinding($alarm.minutes), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Menu {
                    Button("当天") { alarm.dayBefore = false }
                    Button("前一天") { alarm.dayBefore = true }
                } label: {
                    HStack(spacing: 3) {
                        Text(alarm.dayBefore ? String(localized: "前一天") : String(localized: "当天"))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline)
                }
                Spacer()
                Toggle("开启闹钟", isOn: $alarm.enabled).labelsHidden()
            }
            if !alarm.dayBefore && alarm.minutes > startMinutes {
                Text("这个时间晚于上班时间，不会响。请提前，或改成「前一天」。")
                    .font(.footnote).foregroundStyle(.red)
            }
        }
        .opacity(alarm.enabled ? 1 : 0.5)
    }
}

struct ReminderPermissionRows: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isPro {
            if model.notificationsNeedPermission && (model.data.reminderEnabled || model.data.eveningReminderEnabled ||
                ((model.data.alarmDelivery == .notification || !ShiftAlarmScheduler.isAuthorized) &&
                 model.data.types.contains { !$0.isOff && $0.alarms.contains { $0.enabled } })) {
                Section { Button("允许通知") { Task { await model.authorizeNotifications() } } }
            }
            if model.alarmsNeedPermission && model.data.alarmDelivery == .alarm && ShiftAlarmScheduler.isAvailable {
                Section { Button("允许班次闹钟") { Task { await model.authorizeShiftAlarms() } } }
            }
            if model.notificationsDenied {
                Section {
                    Label("通知权限已关闭，普通提醒无法送达。", systemImage: "bell.slash")
                    Button("去设置打开") { openBanLiSettings() }
                }
            }
            if model.alarmsDenied && model.data.alarmDelivery == .alarm && ShiftAlarmScheduler.isAvailable {
                Section {
                    Label("闹钟权限已关闭，班次闹钟不会响铃。", systemImage: "alarm")
                    Button("去设置打开") { openBanLiSettings() }
                }
            }
            if let status = model.reminderStatus {
                Section {
                    Text(status).foregroundStyle(.secondary)
                    Button("重试") { model.refreshReminders() }
                }
            }
        }
    }
}

private func reminderClockBinding(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding(get: {
        ScheduleData.clockDate(minutes: minutes.wrappedValue, on: Date(), calendar: .banli) ?? Date()
    }, set: { date in
        let parts = Calendar.banli.dateComponents([.hour, .minute], from: date)
        minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    })
}

private func alarmSummary(_ type: ShiftType) -> String {
    let on = type.alarms.filter(\.enabled)
    guard !on.isEmpty else { return String(localized: "未设置") }
    let times = on.prefix(3).map { ($0.dayBefore ? String(localized: "前一天") + " " : "") + ShiftType.clock($0.minutes) }
    let isChinese = (Locale.preferredLanguages.first ?? "").hasPrefix("zh")
    return times.joined(separator: isChinese ? "、" : ", ") + (on.count > 3 ? "…" : "")
}

private func openBanLiSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}
