import SwiftUI
import UIKit


struct TipsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @AppStorage("hideAlarmPrompt") private var hideAlarmPrompt = false
    @State private var showReminders = false

    private var needsAlarmPrompt: Bool {
        let d = model.data
        return !hideAlarmPrompt && !d.reminderEnabled && !d.eveningReminderEnabled
            && !d.types.contains { $0.alarms.contains { $0.enabled } }
    }

    var body: some View {
        let tips = TipEngine.tips(data: model.data, now: Date(), weather: model.weather)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("温馨提示").font(.headline)
                Spacer()
                if let w = model.weather, let h = w.hour(near: Date()) {
                    HStack(spacing: 5) {
                        Image(systemName: h.symbol).symbolRenderingMode(.multicolor)
                        Text("\(Int(h.temperature.rounded()))°").fontWeight(.semibold)
                        if let place = w.place {
                            Text(place).foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                } else if model.weatherLoading {
                    ProgressView().controlSize(.small)
                }
            }

            ForEach(tips) { tip in
                HStack(spacing: 12) {
                    Image(systemName: tip.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.accentColor.opacity(0.12)))
                    Text(tip.text).font(.subheadline)
                    Spacer(minLength: 0)
                }
            }

            if needsAlarmPrompt {
                HStack(spacing: 8) {
                    Button {
                        showReminders = true
                    } label: {
                        Label("设置上班闹钟，倒班不怕睡过头", systemImage: "alarm.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    Button {
                        hideAlarmPrompt = true
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("关闭"))
                }
            }

            if !model.weatherEnabled {
                Button {
                    Task { await model.enableWeather() }
                } label: {
                    Label("开启天气，上下班提醒带伞、加衣", systemImage: "cloud.sun.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } else if let w = model.weather {
                attribution(w)
            }
        }
        .padding(18)
        .card()
        .sheet(isPresented: $showReminders) {
            NavigationStack {
                ReminderSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { showReminders = false }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func attribution(_ w: WeatherSnapshot) -> some View {
        HStack(spacing: 6) {
            if let url = scheme == .dark ? w.markDarkURL : w.markLightURL {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Text("Apple 天气")
                }
                .frame(height: 11)
            } else {
                Text("天气数据：Apple 天气")
            }
            if let legal = w.legalURL {
                Link("数据来源说明", destination: legal)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}


struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareMonthView: View {
    let data: ScheduleData
    let month: Date

    private var cal: Calendar { .banli }

    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let days: [Date?] = range.map { cal.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: lead) + days
    }

    private var weeks: [[Date?]] {
        var all = cells
        while all.count % 7 != 0 { all.append(nil) }
        return stride(from: 0, to: all.count, by: 7).map { Array(all[$0..<$0 + 7]) }
    }

    @ViewBuilder
    private func cell(_ day: Date?) -> some View {
        if let day {
            let s = data.shift(on: day)
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(s == nil ? Color.primary : Color.white.opacity(0.9))
                Text(s?.displayName ?? "")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(s?.color ?? Color.gray.opacity(0.15))
            )
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 50)
        }
    }

    var body: some View {
        let c = cal.dateComponents([.year], from: month)
        let stats = data.monthStats(for: month)

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(month.formatted(.dateTime.month(.wide)))排班")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                Text("\(String(c.year ?? 0))年 · \(data.displayTemplateName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    ForEach(Array((Array(cal.veryShortStandaloneWeekdaySymbols.dropFirst()) + [cal.veryShortStandaloneWeekdaySymbols[0]]).enumerated()), id: \.offset) { _, w in
                        Text(w).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(weeks.indices, id: \.self) { wi in
                    HStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { di in
                            cell(weeks[wi][di])
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(stats.indices, id: \.self) { i in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(stats[i].type.color).frame(width: 10, height: 10)
                        Text("\(stats[i].type.displayName) \(stats[i].days)天").font(.caption)
                    }
                }
            }

            HStack(spacing: 10) {
                if let url = AppConfig.appStoreURL, let qr = QRCode.image(for: url.absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 54, height: 54)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("班历 · 倒班排班日历").font(.caption.weight(.semibold))
                    Text(AppConfig.appStoreURL == nil ? String(localized: "App Store 搜「班历」免费下载") : String(localized: "扫码或在 App Store 搜「班历」"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.gray.opacity(0.08)))
        }
        .padding(26)
        .frame(width: 400)
        .background(Color.white)
    }

    @MainActor
    static func render(data: ScheduleData, month: Date) -> UIImage {
        let renderer = ImageRenderer(
            content: ShareMonthView(data: data, month: month).environment(\.colorScheme, .light)
        )
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }
}

struct SharePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let image: UIImage

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                    .padding(20)

                ShareLink(item: ShareCode.message(for: model.data)) {
                    Label("同事要用？发班组口令，一键导入", systemImage: "person.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("分享本月排班")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview(String(localized: "本月排班"), image: Image(uiImage: image))) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
