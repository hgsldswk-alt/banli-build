import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false
    @State private var confirmClear = false
    @State private var editingCurrent: CustomSchedule?
    @State private var openCycle = LaunchArgs.has("-cycle")
    @State private var openPicker = LaunchArgs.has("-picker")
    @State private var openReminders = LaunchArgs.has("-reminders")
    @State private var openAlarms = LaunchArgs.has("-alarms")

    var body: some View {
        NavigationStack {
            Form {
                Section("排班规则") {
                    NavigationLink {
                        TemplatePickerView()
                    } label: {
                        LabeledContent("排班方式", value: model.data.displayTemplateName)
                    }
                    Button {
                        editingCurrent = model.editableCurrent()
                    } label: {
                        Label("改当前排班：天数、上下班时间", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink("今天是循环的第几天") { TodayPositionView() }
                }

                Section {
                    ShareCodeRows()
                    ImportCodeRow()
                } header: {
                    Text("班组共享")
                } footer: {
                    Text("同一个班组排班一样：一个人排好，发口令到群里，大家一键导入。口令里只有班次和循环，不含备注和单日调班。")
                }

                if !Launch.isFree {
                    Section {
                        ProBanner(isPro: model.isPro, price: model.product?.displayPrice ?? String(localized: "查看价格")) {
                            showPaywall = true
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    NavigationLink { ReminderSettingsView() } label: {
                        Label("提醒设置", systemImage: "bell.badge")
                    }
                    NavigationLink("桌面和锁屏小组件") { WidgetGuideView() }
                } header: {
                    Text("高级版")
                } footer: {
                    Text("一次买断，以后不再收费。")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { model.weatherEnabled },
                        set: { on in
                            if on {
                                Task { await model.enableWeather() }
                            } else {
                                WeatherCache.enabled = false
                                model.weatherEnabled = false
                            }
                        }
                    )) {
                        Label("天气提醒", systemImage: "cloud.sun")
                    }
                } header: {
                    Text("温馨提示")
                } footer: {
                    Text("开启后按你所在城市的天气，提醒上下班带伞、加衣。只在打开 App 时更新，最多每小时一次。")
                }

                Section {
                    Button("清除所有单日调班", role: .destructive) { confirmClear = true }
                        .disabled(model.data.overrides.isEmpty)
                    Button("恢复购买") { Task { await model.restore() } }
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.appVersion)
                    Text("所有排班数据只保存在你的手机上，不联网上传，不收集任何个人信息。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .onAppear {
                if openCycle {
                    openCycle = false
                    editingCurrent = model.editableCurrent()
                }
            }
            .navigationDestination(isPresented: $openPicker) { TemplatePickerView() }
            .sheet(item: $editingCurrent) { draft in
                NavigationStack {
                    CustomScheduleEditor(schedule: draft, isNew: false, replacesCurrent: true) {
                        editingCurrent = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { editingCurrent = nil }
                        }
                    }
                }
                .interactiveDismissDisabled()
            }
            .navigationDestination(isPresented: $openReminders) { ReminderSettingsView() }
            .navigationDestination(isPresented: $openAlarms) {
                if let type = model.data.types.first(where: { !$0.isOff }) {
                    ShiftAlarmsView(typeID: type.id)
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .confirmationDialog("清除后，所有单日调班都恢复成循环排班。", isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("清除", role: .destructive) { model.data.overrides = [:] }
            }
        }
    }
}

private struct ProBanner: View {
    let isPro: Bool
    let price: String
    let action: () -> Void

    var body: some View {
        Button {
            if !isPro { action() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isPro ? "checkmark.seal.fill" : "crown.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isPro ? String(localized: "已解锁高级版") : String(localized: "班历高级版"))
                        .font(.headline)
                    Text(isPro ? String(localized: "小组件、闹钟和锁屏实时显示都能用了") : String(localized: "小组件 · 班次闹钟 · 锁屏实时显示"))
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer()
                if !isPro {
                    Text(price)
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white))
                        .foregroundStyle(Color(hex: "E8763A"))
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(
                LinearGradient(colors: [Color(hex: "F7A858"), Color(hex: "E8763A")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}


struct TemplatePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onImported: (() -> Void)? = nil
    var onFinished: (() -> Void)? = nil
    var title = String(localized: "选择排班方式")

    private struct EditorTarget: Identifiable {
        let id = UUID()
        let schedule: CustomSchedule
        let isNew: Bool
    }

    @State private var editor: EditorTarget?
    @State private var deleting: CustomSchedule?
    @State private var switching: CustomSchedule?

    var body: some View {
        List {
            if let onImported {
                Section {
                    ImportCodeRow(onImported: onImported)
                }
            }

            if !model.customSchedules.isEmpty {
                Section {
                    ForEach(model.customSchedules) { c in
                        HStack(spacing: 8) {
                            Button {
                                use(c)
                            } label: {
                                ScheduleRow(name: c.name,
                                            detail: String(localized: "一个循环 \(c.cycle.count) 天"),
                                            chips: c.cycle.compactMap { c.type(id: $0) }.map { ($0.displayName, $0.colorHex) },
                                            selected: model.data.customID == c.id)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button {
                                editor = EditorTarget(schedule: c, isNew: false)
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("编辑"))
                            .accessibilityIdentifier("editSchedule")
                        }
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) { deleting = c }
                            Button("编辑") { editor = EditorTarget(schedule: c, isNew: false) }
                                .tint(.orange)
                        }
                    }
                } header: {
                    Text("我的排班")
                } footer: {
                    Text("点一下就换成这套。点铅笔改名字、班次和时间，左滑删除。")
                }
            }

            Section {
                ForEach(ScheduleTemplate.all) { t in
                    Button {
                        let start = t.id == "custom"
                            ? CustomSchedule.blank(name: CustomSchedule.defaultName(existing: model.customSchedules))
                            : CustomSchedule.from(t)
                        editor = EditorTarget(schedule: start, isNew: true)
                    } label: {
                        ScheduleRow(name: t.name, detail: t.detail,
                                    chips: t.pattern.map { (t.kinds[$0].name, t.kinds[$0].colorHex) },
                                    selected: false)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(model.customSchedules.isEmpty ? String(localized: "选一个最接近的，下一步可以改") : String(localized: "从模板新建"))
            } footer: {
                Text("点开后在同一页里改名字、天数、上下班时间，再点一下今天是哪天，保存就好。")
            }
        }
        .navigationTitle(title)
        .confirmationDialog(
            "换成「\(switching?.name ?? "")」会清空现在的单日调班；备注和提醒设置会保留。",
            isPresented: Binding(get: { switching != nil }, set: { if !$0 { switching = nil } }),
            titleVisibility: .visible
        ) {
            Button("换") {
                if let switching { model.applyCustom(switching) }
                switching = nil
            }
        }
        .confirmationDialog(
            "删除「\(deleting?.name ?? "")」？删除后不能恢复；如果正在用它，日历照旧不变。",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let deleting { model.deleteCustom(id: deleting.id) }
                deleting = nil
            }
        }
        .sheet(item: $editor) { target in
            NavigationStack {
                CustomScheduleEditor(schedule: target.schedule, isNew: target.isNew) {
                    editor = nil
                    onFinished?()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editor = nil }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private func use(_ c: CustomSchedule) {
        guard model.data.customID != c.id else {
            onFinished?()
            return
        }
        if model.data.overrides.isEmpty || onFinished != nil {
            model.applyCustom(c)
            onFinished?()
        } else {
            switching = c
        }
    }
}

private struct ScheduleRow: View {
    let name: String
    let detail: String
    let chips: [(String, String)]
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(BuiltInNames.localized(name)).font(.headline).foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Array(chips.prefix(12).enumerated()), id: \.offset) { _, chip in
                    Text(String(BuiltInNames.localized(chip.0).prefix(1)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: chip.1)))
                }
                if chips.count > 12 {
                    Text("…").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}


struct TodayPositionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onDone: (() -> Void)? = nil

    var body: some View {
        let todayIndex = model.data.cycleIndex(on: Date())
        List {
            Section {
                ForEach(Array(model.data.cycle.enumerated()), id: \.offset) { i, id in
                    Button {
                        model.setToday(isCycleDay: i)
                        if let onDone { onDone() } else { dismiss() }
                    } label: {
                        HStack(spacing: 12) {
                            Text("第 \(i + 1) 天").foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                            if let t = model.data.type(id: id) {
                                ShiftChip(type: t, size: 26)
                                Text(t.displayName).foregroundStyle(.primary)
                            }
                            Spacer()
                            if todayIndex == i {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("今天上的是循环里的哪一天？")
            } footer: {
                Text("比如两班倒今天是第二个夜班，就选对应的那一天。选好后整个日历会自动排好。")
            }
        }
        .navigationTitle("今天是第几天")
    }
}


struct WidgetGuideView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if !model.isPro {
                Section {
                    Text("小组件是高级版功能。没解锁时，小组件上会提示解锁。")
                        .foregroundStyle(.secondary)
                }
            }
            Section("加到桌面") {
                Text("1. 在桌面空白处长按，直到图标开始晃动")
                Text("2. 点左上角「编辑」→「添加小组件」")
                Text("3. 搜索「班历」，选大小后点「添加小组件」")
            }
            Section("加到锁屏") {
                Text("1. 在锁屏长按，点「自定」→「锁定屏幕」")
                Text("2. 点时间下方的小组件区域")
                Text("3. 选「班历」")
            }
        }
        .navigationTitle("小组件")
    }
}

extension Bundle {
    var appVersion: String {
        let v = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}
