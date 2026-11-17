import SwiftUI


struct CustomScheduleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CustomSchedule
    @State private var todayIndex: Int
    private let replacesCurrent: Bool
    private let isNew: Bool
    private let onFinish: (() -> Void)?

    @State private var confirmDelete = false
    @State private var pendingSave: CustomSchedule?
    private let anchorDay = Calendar.banli.startOfDay(for: Date())

    init(schedule: CustomSchedule, isNew: Bool, replacesCurrent: Bool = false, onFinish: (() -> Void)? = nil) {
        _draft = State(initialValue: schedule)
        _todayIndex = State(initialValue: schedule.todayIndex(now: Calendar.banli.startOfDay(for: Date())))
        self.isNew = isNew
        self.replacesCurrent = replacesCurrent
        self.onFinish = onFinish
    }

    var body: some View {
        List {
            Section {
                TextField("比如：A 组、夏季排班", text: $draft.name)
                    .font(.headline)
                    .submitLabel(.done)
            } header: {
                Text("名称")
            }

            Section {
                CyclePreview(cycle: draft.cycle, types: draft.types, today: todayIndex) { i in
                    todayIndex = i
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                if let t = draft.cycle.indices.contains(todayIndex) ? draft.type(id: draft.cycle[todayIndex]) : nil {
                    Text("今天是第 \(todayIndex + 1) 天：\(t.displayName)")
                        .font(.subheadline.weight(.semibold))
                }
            } header: {
                Text("一个循环 \(draft.cycle.count) 天")
            } footer: {
                Text("点一下色块，标出今天上的是哪一天，整个日历就按它排好。")
            }

            runsSection
            typesSection

            if !isNew && !replacesCurrent {
                Section {
                    Button("删除这套排班", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(isNew ? String(localized: "新建自定义排班") : String(localized: "编辑排班"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text(isNew || (!replacesCurrent && model.data.customID != draft.id)
                     ? String(localized: "保存并使用") : String(localized: "保存"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("saveSchedule")
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .confirmationDialog("换成这套会清空现在的单日调班；备注和提醒设置会保留。",
                            isPresented: Binding(get: { pendingSave != nil }, set: { if !$0 { pendingSave = nil } }),
                            titleVisibility: .visible) {
            Button("保存并使用") {
                if let c = pendingSave { commit(c) }
                pendingSave = nil
            }
        }
        .confirmationDialog("删除「\(draft.name)」？删除后不能恢复；如果正在用它，日历照旧不变。",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                model.deleteCustom(id: draft.id)
                finish()
            }
        }
    }


    private var runsSection: some View {
        let runs = draft.runs
        return Section {
            ForEach(Array(runs.enumerated()), id: \.offset) { i, run in
                HStack(spacing: 10) {
                    Menu {
                        ForEach(draft.types) { t in
                            Button {
                                updateRuns { if $0.indices.contains(i) { $0[i].typeID = t.id } }
                            } label: {
                                Label(t.displayName, systemImage: t.id == run.typeID ? "checkmark" : "circle")
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if let t = draft.type(id: run.typeID) {
                                ShiftChip(type: t, size: 28)
                                Text(t.displayName).foregroundStyle(.primary)
                            }
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Stepper(value: Binding(
                        get: { run.count },
                        set: { n in updateRuns { if $0.indices.contains(i) { $0[i].count = n } } }
                    ), in: 1...31) {
                        Text("\(run.count) 天").monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .fixedSize()
                }
            }
            .onMove { from, to in updateRuns { $0.move(fromOffsets: from, toOffset: to) } }
            .onDelete { idx in
                guard runs.count - idx.count >= 1 else { return }
                updateRuns { $0.remove(atOffsets: idx) }
            }

            Button {
                let last = runs.last?.typeID
                if let next = draft.types.first(where: { $0.id != last }) ?? draft.types.first {
                    updateRuns { $0.append(CycleRun(typeID: next.id, count: 1)) }
                }
            } label: {
                Label("加一段", systemImage: "plus.circle")
            }
        } header: {
            Text("循环：上什么班、连上几天")
        } footer: {
            Text("比如「白班 3 天、休息 2 天」就是上三休二。左滑删除一段，点右上角「编辑」可以拖动排序。")
        }
    }

    private func updateRuns(_ change: (inout [CycleRun]) -> Void) {
        var r = draft.runs
        change(&r)
        guard !r.isEmpty else { return }
        draft.runs = r
        todayIndex = min(todayIndex, max(draft.cycle.count - 1, 0))
    }


    private var typesSection: some View {
        Section {
            ForEach(draft.types) { t in
                ShiftTypeInlineRow(type: typeBinding(t.id, fallback: t))
                    .swipeActions(edge: .trailing) {
                        if draft.types.count > 1 {
                            Button("删除", role: .destructive) { draft.removeType(id: t.id) }
                        }
                    }
            }
            Button {
                let used = Set(draft.types.map(\.colorHex))
                let color = ShiftPalette.colors.first { !used.contains($0) } ?? ShiftPalette.colors[0]
                draft.types.append(ShiftType(name: String(localized: "新班次"), colorHex: color,
                                             startMinutes: 9 * 60, endMinutes: 18 * 60))
            } label: {
                Label("新增班次", systemImage: "plus.circle")
            }
        } header: {
            Text("班次和上下班时间")
        } footer: {
            Text("点名字直接改，点色块换颜色。新增的班次加到上面的循环里才会排进日历。左滑删除班次。")
        }
    }

    private func typeBinding(_ id: UUID, fallback: ShiftType) -> Binding<ShiftType> {
        Binding(
            get: { draft.types.first { $0.id == id } ?? fallback },
            set: { v in
                if let i = draft.types.firstIndex(where: { $0.id == id }) { draft.types[i] = v }
            }
        )
    }


    private func save() {
        var c = draft
        c.name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.name.isEmpty {
            c.name = CustomSchedule.defaultName(existing: model.customSchedules.filter { $0.id != c.id })
        }
        for i in c.types.indices where c.types[i].name.trimmingCharacters(in: .whitespaces).isEmpty {
            c.types[i].name = c.types[i].isOff ? String(localized: "休息") : String(localized: "班次")
        }
        let idx = min(max(todayIndex, 0), max(c.cycle.count - 1, 0))
        c.cycleStart = Calendar.banli.date(byAdding: .day, value: -idx, to: anchorDay) ?? anchorDay

        let switching = !replacesCurrent && model.data.customID != model.resolvedCustomID(for: c)
        if switching && !model.data.overrides.isEmpty {
            pendingSave = c
        } else {
            commit(c)
        }
    }

    private func commit(_ c: CustomSchedule) {
        model.saveCustom(c, replacesCurrent: replacesCurrent)
        finish()
    }

    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }
}

private struct ShiftTypeInlineRow: View {
    @Binding var type: ShiftType

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Menu {
                    Picker("颜色", selection: $type.colorHex) {
                        ForEach(ShiftPalette.colors, id: \.self) { hex in
                            Label(hex, systemImage: "circle.fill")
                                .tint(Color(hex: hex))
                                .tag(hex)
                        }
                    }
                    .pickerStyle(.palette)
                    Divider()
                    Button(type.isOff ? String(localized: "改成上班") : String(localized: "改成休息日")) {
                        type.isOff.toggle()
                    }
                } label: {
                    ShiftChip(type: type, size: 30)
                }
                TextField("班次名称", text: $type.name)
                    .font(.body.weight(.medium))
            }
            if type.isOff {
                Text("休息日").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Text("上班").font(.subheadline).foregroundStyle(.secondary)
                    DatePicker("上班", selection: clock(\.startMinutes), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer(minLength: 4)
                    Text("下班").font(.subheadline).foregroundStyle(.secondary)
                    DatePicker("下班", selection: clock(\.endMinutes), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                if type.endMinutes % 1440 <= type.startMinutes % 1440 {
                    Text("跨夜：第二天 \(ShiftType.clock(type.endMinutes)) 下班")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func clock(_ key: WritableKeyPath<ShiftType, Int>) -> Binding<Date> {
        Binding(
            get: {
                let cal = Calendar.banli
                let m = ((type[keyPath: key] % 1440) + 1440) % 1440
                return cal.date(byAdding: .minute, value: m, to: cal.startOfDay(for: Date())) ?? Date()
            },
            set: { date in
                let c = Calendar.banli.dateComponents([.hour, .minute], from: date)
                type[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

struct CyclePreview: View {
    let cycle: [UUID]
    let types: [ShiftType]
    var today: Int? = nil
    var onTap: ((Int) -> Void)? = nil

    var body: some View {
        let byID = Dictionary(types.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(Array(cycle.enumerated()), id: \.offset) { i, id in
                if let t = byID[id] {
                    VStack(spacing: 2) {
                        ShiftChip(type: t, size: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(Color.primary, lineWidth: today == i ? 2.5 : 0)
                                    .padding(-3)
                            )
                        Text(today == i ? String(localized: "今天") : "\(i + 1)")
                            .font(.caption2.weight(today == i ? .bold : .regular))
                            .foregroundStyle(today == i ? Color.primary : Color.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?(i) }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("cycleDay-\(i)")
                    .accessibilityAddTraits(onTap == nil ? [] : .isButton)
                }
            }
        }
    }
}
