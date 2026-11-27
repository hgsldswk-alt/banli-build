import SwiftUI

struct CalendarScreen: View {
    let isHomeVisible: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.requestReview) private var requestReview
    @State private var month = Calendar.banli.startOfMonth(Date())
    @State private var editing: EditDay?
    @State private var shareImage: ShareImage?

    private let cal = Calendar.banli

    struct EditDay: Identifiable {
        let date: Date
        var id: String { DayKey.key(for: date) }
    }

    init(isHomeVisible: Bool) {
        self.isHomeVisible = isHomeVisible
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    MilestonePrompt(isVisible: isHomeVisible && editing == nil && shareImage == nil) {
                        TodayHero(data: model.data)
                    }
                    TipsCard()
                    monthCard
                    statsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("班历")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        shareImage = ShareImage(image: ShareMonthView.render(data: model.data, month: month))
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享本月排班")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) { month = cal.startOfMonth(Date()) }
                    } label: {
                        Text("今天")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    }
                }
            }
            .sheet(item: $editing) { day in
                DayEditSheet(date: day.date)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(28)
            }
            .sheet(item: $shareImage) { item in
                SharePreviewSheet(image: item.image)
            }
            .task {
                try? await Task.sleep(for: .seconds(2))
                if ReviewGate.shouldAsk() { requestReview() }
            }
            .onAppear {
                if LaunchArgs.has("-share") {
                    shareImage = ShareImage(image: ShareMonthView.render(data: model.data, month: month))
                }
                if LaunchArgs.has("-dayedit"), let d = cal.date(byAdding: .day, value: 2, to: Date()) {
                    editing = EditDay(date: d)
                }
            }
        }
    }


    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: month)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        let days: [Date?] = range.map { cal.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: lead) + days
    }

    private func moveMonth(_ delta: Int) {
        withAnimation(.snappy) {
            month = cal.date(byAdding: .month, value: delta, to: month) ?? month
        }
    }

    private var monthCard: some View {
        let c = cal.dateComponents([.year], from: month)
        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(String(c.year ?? 0))
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                CircleButton(systemName: "chevron.left") { moveMonth(-1) }
                CircleButton(systemName: "chevron.right") { moveMonth(1) }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(Array((Array(cal.veryShortStandaloneWeekdaySymbols.dropFirst()) + [cal.veryShortStandaloneWeekdaySymbols[0]]).enumerated()), id: \.offset) { i, w in
                    Text(w)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(i >= 5 ? Color.accentColor : Color.secondary)
                        .padding(.bottom, 2)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(
                            date: day,
                            shift: model.data.shift(on: day),
                            isToday: cal.isDateInToday(day),
                            adjusted: model.data.isOverridden(day),
                            hasNote: model.data.note(on: day) != nil,
                            holiday: Holidays.info(for: day),
                            refresh: model.holidayVersion
                        )
                        .onTapGesture { editing = EditDay(date: day) }
                    } else {
                        Color.clear.frame(height: 66)
                    }
                }
            }
            .id(month)
            .transition(.opacity)

            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                Text("点某天可调班、写备注；橙点是调过班的日子")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(18)
        .card()
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -50 { moveMonth(1) }
                if v.translation.width > 50 { moveMonth(-1) }
            }
        )
    }


    private var statsCard: some View {
        let stats = model.data.monthStats(for: month)
        let work = stats.filter { !$0.type.isOff }.reduce(0) { $0 + $1.days }
        let off = stats.filter { $0.type.isOff }.reduce(0) { $0 + $1.days }
        let minutes = model.data.monthWorkMinutes(for: month)
        let hoursText = minutes % 60 == 0 ? "\(minutes / 60)" : String(format: "%.1f", Double(minutes) / 60)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("本月概览").font(.headline)
                Spacer()
                Text("上班 \(work) 天 · 休息 \(off) 天")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "clock.fill").font(.subheadline).foregroundStyle(Color.accentColor)
                Text("本月工时").font(.subheadline).foregroundStyle(.secondary)
                Text(hoursText).font(.system(size: 24, weight: .bold, design: .rounded))
                Text("小时").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(stats.indices, id: \.self) { i in
                    let s = stats[i]
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: s.type.symbol).font(.caption2)
                            Text(s.type.displayName).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(s.type.color)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(s.days)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("天").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(s.type.color.opacity(0.10))
                    )
                }
            }
        }
        .padding(18)
        .card()
    }
}


struct TodayHero: View {
    let data: ScheduleData

    var body: some View {
        let cal = Calendar.banli
        let today = Date()
        let shift = data.shift(on: today)
        let tomorrowDate = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let tomorrow = data.shift(on: tomorrowDate)
        let base = shift?.color ?? Color.gray

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今天 · \(cal.monthDayCN(today))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(shift?.displayName ?? String(localized: "未设置"))
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let shift, !shift.isOff {
                        Label(shift.timeText, systemImage: "clock")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    } else {
                        Text("好好休息")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("明天").font(.caption2.weight(.medium)).opacity(0.8)
                    Text(tomorrow?.displayName ?? "—").font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.18)))
            }

            Spacer(minLength: 18)

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let day = cal.date(byAdding: .day, value: i, to: today) ?? today
                    let s = data.shift(on: day)
                    VStack(spacing: 5) {
                        Text(i == 0 ? String(localized: "今") : cal.weekdayCN(day))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(s?.shortName ?? "—")
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .foregroundStyle(i == 0 ? base : .white)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(i == 0 ? Color.white : Color.white.opacity(0.18))
                            )
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [base, base.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: shift?.symbol ?? "calendar")
                    .font(.system(size: 150, weight: .bold))
                    .foregroundStyle(.white.opacity(0.12))
                    .offset(x: 30, y: -30)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: base.opacity(0.35), radius: 18, x: 0, y: 10)
        .animation(.snappy, value: shift?.id)
    }
}


struct DayCell: View {
    let date: Date
    let shift: ShiftType?
    let isToday: Bool
    let adjusted: Bool
    var hasNote: Bool = false
    var holiday: HolidayDay? = nil
    var refresh: Int = 0

    private var subText: String {
        if LocaleFeatures.current.showsChinaHolidays, let holiday, holiday.isOffDay { return holiday.displayName }
        return LocaleFeatures.current.showsLunar ? Lunar.shortText(date) : ""
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Calendar.banli.component(.day, from: date))")
                .font(.system(.subheadline, design: .rounded).weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color(.systemBackground) : .primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isToday ? Color.primary : Color.clear))
            if !subText.isEmpty || hasNote {
                HStack(spacing: 1) {
                    if hasNote {
                        Image(systemName: "pencil").font(.system(size: 7, weight: .bold))
                    }
                    Text(subText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(LocaleFeatures.current.showsChinaHolidays && holiday?.isOffDay == true ? Color.red : Color.secondary)
                .frame(height: 11)
            }
            Text(shift?.shortName ?? " ")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(shift?.color ?? .clear)
                .frame(maxWidth: 30, minHeight: 18)
                .background(Capsule().fill((shift?.color ?? .clear).opacity(0.16)))
        }
        .frame(maxWidth: .infinity, minHeight: 66)
        .overlay(alignment: .topLeading) {
            if LocaleFeatures.current.showsChinaHolidays, let holiday {
                Text(holiday.isOffDay ? String(localized: "休") : String(localized: "班"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 12, height: 12)
                    .background(RoundedRectangle(cornerRadius: 3).fill(holiday.isOffDay ? Color.red : Color.gray))
                    .padding(.leading, 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if adjusted {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6).padding(.top, 6).padding(.trailing, 8)
            }
        }
        .contentShape(Rectangle())
    }
}


struct DayEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let date: Date

    @State private var noteText = ""

    var body: some View {
        let current = model.data.shift(on: date)
        let cycle = model.data.cycleShift(on: date)
        let holiday = LocaleFeatures.current.showsChinaHolidays ? Holidays.info(for: date) : nil

        NavigationStack {
            List {
                Section {
                    if LocaleFeatures.current.showsLunar || holiday != nil {
                        HStack {
                            if LocaleFeatures.current.showsLunar {
                                Text(Lunar.fullText(date)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let holiday {
                                Text(holiday.isOffDay ? String(localized: "\(holiday.displayName) 放假") : String(localized: "\(holiday.displayName) 调休上班"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(holiday.isOffDay ? Color.red : Color.secondary)
                            }
                        }
                    }
                    TextField("备注，比如：和小王换班", text: $noteText, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("备注")
                }

                Section {
                    ForEach(model.data.types) { t in
                        Button {
                            model.data.setShift(t.id, on: date)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                ShiftChip(type: t)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.displayName).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(t.timeText).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if current?.id == t.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(t.color)
                                }
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("这天上什么班")
                } footer: {
                    Text("按循环这天应该是「\(cycle?.displayName ?? String(localized: "未设置"))」。只改这一天，不影响后面的循环。")
                }

                if model.data.isOverridden(date) {
                    Section {
                        Button {
                            model.data.setShift(nil, on: date)
                            dismiss()
                        } label: {
                            Label("恢复为循环排班", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .navigationTitle(Calendar.banli.monthDayCN(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onAppear { noteText = model.data.note(on: date) ?? "" }
        .onDisappear { saveNote() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { saveNote() } }
    }

    private func saveNote() {
        if noteText != (model.data.note(on: date) ?? "") { model.data.setNote(noteText, on: date) }
    }
}


struct ShiftChip: View {
    let type: ShiftType
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: type.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(type.gradient))
    }
}

struct CircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func card() -> some View {
        background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
    }
}
