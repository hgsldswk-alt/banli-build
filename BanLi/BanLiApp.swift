import SwiftUI

@main
struct BanLiApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Color(hex: "F2994A"))
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = (!AppModel.isDemo && !SharedStore.hasOnboarded) || LaunchArgs.has("-onboarding")
    @State private var tab = LaunchArgs.value(after: "-tab").flatMap(Int.init) ?? 0
    @State private var showPaywall = LaunchArgs.has("-paywall")

    var body: some View {
        TabView(selection: $tab) {
            CalendarScreen()
                .tabItem { Label("排班", systemImage: "calendar") }
                .tag(0)
            SettingsScreen()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(1)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                SharedStore.hasOnboarded = true
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .alert("提示", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("好") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                ReviewGate.recordLaunch()
                model.refreshReminders()
                Task {
                    await model.refreshEntitlements()
                    await model.refreshWeather()
                    await model.refreshHolidays()
                }
            }
        }
        .task { model.refreshReminders() }
    }
}

enum LaunchArgs {
    static func has(_ flag: String) -> Bool {
        AppModel.isDemo && ProcessInfo.processInfo.arguments.contains(flag)
    }

    static func value(after flag: String) -> String? {
        guard AppModel.isDemo else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
