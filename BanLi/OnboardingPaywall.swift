import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    var body: some View {
        NavigationStack {
            TemplatePickerView(onImported: onFinish, onFinished: onFinish,
                               title: String(localized: "你是怎么倒班的？"))
        }
    }
}

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private struct Feature: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private let features = [
        Feature(icon: "alarm.fill", title: String(localized: "按班次设闹钟"), detail: String(localized: "早班、夜班各设各的闹钟，调班后自动跟着变，休息日不吵你")),
        Feature(icon: "moon.stars.fill", title: String(localized: "前一晚提醒明天的班"), detail: String(localized: "睡前告诉你明天上什么班、几点上，不用再翻排班表")),
        Feature(icon: "timer", title: String(localized: "锁屏倒计时"), detail: String(localized: "锁屏和灵动岛显示离上班、下班还有多久")),
        Feature(icon: "rectangle.on.rectangle", title: String(localized: "桌面小组件"), detail: String(localized: "不用打开 App，看一眼桌面就知道今天、明天上什么班")),
        Feature(icon: "lock.iphone", title: String(localized: "锁屏小组件"), detail: String(localized: "亮屏就能看到今天的班次")),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 92, height: 92)
                        .background(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(LinearGradient(colors: [Color(hex: "F7A858"), Color(hex: "E8763A")],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: Color(hex: "E8763A").opacity(0.4), radius: 16, y: 8)
                        .padding(.top, 24)
                    Text("班历高级版").font(.system(.title, design: .rounded).bold())
                    Text("一次买断，永久使用").foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(features) { f in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: f.icon)
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.headline)
                                    Text(f.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))

                    Button {
                        Task {
                            await model.purchase()
                            if model.isPro { dismiss() }
                        }
                    } label: {
                        Group {
                            if model.isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                if let price = model.product?.displayPrice {
                                    Text("\(price) 解锁")
                                } else {
                                    Text("解锁高级版")
                                }
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isPurchasing)

                    Button("恢复购买") {
                        Task {
                            await model.restore()
                            if model.isPro { dismiss() }
                        }
                    }
                    .font(.subheadline)

                    Text("排班日历、单日调班、班次统计永久免费。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await model.loadProduct() }
        }
    }
}
