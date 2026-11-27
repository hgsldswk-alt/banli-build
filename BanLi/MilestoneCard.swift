import Combine
import SwiftUI
import UIKit

enum ScheduleMilestone: String, CaseIterable {
    case firstCycle
    case thirtyDays

    static let thirtyDayThreshold = 30

    var title: LocalizedStringKey {
        switch self {
        case .firstCycle: "走完一个轮班周期"
        case .thirtyDays: "班历相伴 30 天"
        }
    }

    var symbol: String {
        switch self {
        case .firstCycle: "arrow.triangle.2.circlepath"
        case .thirtyDays: "checkmark.circle"
        }
    }

    func isEarned(data: ScheduleData, firstLaunch: Date, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .firstCycle:
            let cycleTypes = Set(data.cycle)
            guard cycleTypes.count > 1 else { return false }
            let types = cycleTypes.compactMap { data.type(id: $0) }
            guard types.count == cycleTypes.count, types.contains(where: { !$0.isOff }) else { return false }
            let start = max(data.cycleStart, firstLaunch)
            return calendar.daysBetween(start, now) >= data.cycle.count
        case .thirtyDays:
            return calendar.daysBetween(firstLaunch, now) >= Self.thirtyDayThreshold
        }
    }
}

enum MilestoneDemo {
    static var target: ScheduleMilestone? {
        LaunchArgs.value(after: "-milestone-demo").flatMap(ScheduleMilestone.init(rawValue:))
    }

    static var runID: UUID? {
        LaunchArgs.value(after: "-milestone-test-run").flatMap(UUID.init(uuidString:))
    }

    static func firstLaunch(data: ScheduleData, now: Date, calendar: Calendar) -> Date? {
        guard let target else { return nil }
        switch target {
        case .firstCycle: return data.cycleStart
        case .thirtyDays: return calendar.date(byAdding: .day, value: -ScheduleMilestone.thirtyDayThreshold, to: now)
        }
    }
}

struct MilestonePrompt<Content: View>: View {
    let isVisible: Bool
    private let content: Content
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var milestone: ScheduleMilestone?
    @State private var preview: ShareImage?
    @State private var renderFailed = false

    init(isVisible: Bool, @ViewBuilder content: () -> Content) {
        self.isVisible = isVisible
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            content
            if let milestone {
                VStack(alignment: .leading, spacing: 4) {
                    banner(for: milestone)
                    if renderFailed {
                        Text("分享图生成失败，请重试")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
        .onChange(of: isVisible, initial: true) { _, _ in offerMilestone() }
        .onChange(of: scenePhase) { _, _ in offerMilestone() }
        .onChange(of: model.data) { _, _ in offerMilestone() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            offerMilestone()
        }
        .sheet(item: $preview) { item in
            MilestonePreview(image: item.image)
        }
    }

    private func banner(for milestone: ScheduleMilestone) -> some View {
        HStack(spacing: 0) {
            Button {
                makeCard(for: milestone)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: milestone.symbol)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(milestone.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.leading, 12)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("生成里程碑分享卡"))
            .accessibilityIdentifier("milestone.make")

            Button {
                self.milestone = nil
                renderFailed = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("关闭里程碑提示"))
            .accessibilityIdentifier("milestone.close")
        }
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    @MainActor
    private func offerMilestone() {
        guard isVisible, scenePhase == .active, milestone == nil, preview == nil else { return }
        let now = Date()
        let calendar = Calendar.banli
        let key: String
        let firstLaunch: Date?
        if AppModel.isDemo {
            guard let runID = MilestoneDemo.runID else { return }
            key = "milestone.offered.v1." + runID.uuidString
            firstLaunch = MilestoneDemo.firstLaunch(data: model.data, now: now, calendar: calendar)
        } else {
            key = "milestone.offered.v1"
            firstLaunch = ReviewGate.firstLaunch
        }
        guard let firstLaunch else { return }
        let defaults = UserDefaults.standard
        let offered = defaults.stringArray(forKey: key) ?? []
        guard let next = ScheduleMilestone.allCases.first(where: {
            !offered.contains($0.rawValue) &&
            $0.isEarned(data: model.data, firstLaunch: firstLaunch, now: now, calendar: calendar)
        }) else { return }
        defaults.set(offered + [next.rawValue], forKey: key)
        milestone = next
    }

    @MainActor
    private func makeCard(for milestone: ScheduleMilestone) {
        guard let image = MilestoneCard.render(milestone: milestone, locale: locale) else {
            renderFailed = true
            return
        }
        preview = ShareImage(image: image)
        self.milestone = nil
        renderFailed = false
    }
}

private struct MilestoneCard: View {
    let milestone: ScheduleMilestone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("班历 · 倒班排班日历", systemImage: "calendar")
                .font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 12)
            Image(systemName: milestone.symbol)
                .font(.system(size: 50, weight: .medium))
                .foregroundStyle(Color(hex: "A9521B"))
                .frame(width: 88, height: 88)
                .background(Color(hex: "FCE8D4"), in: RoundedRectangle(cornerRadius: 24))
            Text(milestone.title)
                .font(.system(size: 39, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 12)
            downloadFooter
        }
        .padding(28)
        .frame(width: 360, height: 450, alignment: .leading)
        .background(Color(hex: "FFF7EE"))
        .foregroundStyle(Color(hex: "29231E"))
    }

    private var downloadFooter: some View {
        let qr = AppConfig.appStoreURL.flatMap { QRCode.image(for: $0.absoluteString) }
        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "#倒班日历  #ShiftWork\n#輪班日曆")
                    .font(.system(size: 14, weight: .semibold))
                if qr != nil {
                    Text("扫码或在 App Store 搜「班历」")
                        .font(.system(size: 12))
                } else {
                    Text("App Store 搜「班历」免费下载")
                        .font(.system(size: 12))
                }
            }
            Spacer(minLength: 0)
            if let qr {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .padding(10)
                    .background(.white)
            }
        }
    }

    @MainActor
    static func render(milestone: ScheduleMilestone, locale: Locale) -> UIImage? {
        let renderer = ImageRenderer(content: MilestoneCard(milestone: milestone)
            .environment(\.locale, locale)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .medium))
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct MilestonePreview: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var shareRequested = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                        .accessibilityLabel(Text("里程碑分享卡"))
                        .accessibilityIdentifier("milestone.preview")
                    if shareRequested, let pixels = image.cgImage {
                        Text(verbatim: "\(pixels.width)×\(pixels.height)")
                            .accessibilityIdentifier("share.requested")
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("里程碑分享卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("milestone.preview.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if MilestoneDemo.runID != nil {
                        Button("分享") { shareRequested = true }
                            .accessibilityIdentifier("milestone.share")
                    } else {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview(String(localized: "里程碑分享卡"), image: Image(uiImage: image))) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("milestone.share")
                    }
                }
            }
        }
    }
}
