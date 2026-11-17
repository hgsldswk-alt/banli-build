import Foundation
import Observation
import StoreKit
import SwiftUI
import WidgetKit
import UserNotifications

@MainActor
@Observable
final class AppModel {
    var data: ScheduleData {
        didSet {
            guard data != oldValue else { return }
            SharedStore.save(data)
            WidgetCenter.shared.reloadAllTimelines()
            refreshReminders()
        }
    }

    var isPro: Bool {
        didSet {
            guard isPro != oldValue else { return }
            SharedStore.isPro = isPro
            WidgetCenter.shared.reloadAllTimelines()
            refreshReminders()
        }
    }

    var customSchedules: [CustomSchedule] = [] {
        didSet {
            guard customSchedules != oldValue, !Self.isDemo else { return }
            SharedStore.saveCustom(customSchedules)
        }
    }

    var product: Product?
    var isPurchasing = false
    var alertMessage: String?

    var weather: WeatherSnapshot? = WeatherCache.load()
    var weatherEnabled: Bool = WeatherCache.enabled
    var weatherLoading = false
    var holidayVersion = 0

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    @ObservationIgnored private var remindersDirty = false
    var notificationsDenied = false
    var alarmsDenied = false
    var notificationsNeedPermission = false
    var alarmsNeedPermission = false
    var activitiesAllowed = true
    var reminderStatus: String?

    nonisolated static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    init() {
        if Self.isDemo {
            var demo = ScheduleTemplate.all[1].makeData()
            demo.setToday(isCycleDay: 2)
            if let day = Calendar.banli.date(byAdding: .day, value: 9, to: Date()) {
                demo.setShift(demo.types.last?.id, on: day)
            }
            demo.reminderEnabled = true
            demo.eveningReminderEnabled = true
            demo.types[0].alarms = [ShiftAlarm(minutes: 6 * 60), ShiftAlarm(minutes: 6 * 60 + 10)]
            if let day = Calendar.banli.date(byAdding: .day, value: 2, to: Date()) {
                demo.setNote(String(localized: "和小王换班"), on: day)
            }
            data = demo
            var team = CustomSchedule.blank(name: String(localized: "A 组（上三休二）"))
            team.types[0].name = String(localized: "白班")
            customSchedules = [team]
            weather = Self.demoWeather()
            weatherEnabled = true
            isPro = !ProcessInfo.processInfo.arguments.contains("-free")
            return
        }
        data = SharedStore.load()
        isPro = Launch.isFree || SharedStore.isPro
        customSchedules = SharedStore.loadCustom()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result {
                    await t.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }


    func applyTemplate(_ template: ScheduleTemplate) {
        var new = template.makeData()
        new.copyReminderSettings(from: data)
        new.notes = data.notes
        data = new
    }

    func applyCustom(_ c: CustomSchedule) {
        var new = ScheduleData(types: c.types, cycle: c.cycle,
                               cycleStart: c.cycleStart ?? Calendar.banli.startOfDay(for: Date()), overrides: [:],
                               reminderEnabled: data.reminderEnabled,
                               reminderMinutesBefore: data.reminderMinutesBefore,
                               templateName: c.name, notes: data.notes)
        new.copyReminderSettings(from: data)
        new.customID = c.id
        data = new
    }

    func resolvedCustomID(for c: CustomSchedule) -> UUID {
        if !customSchedules.contains(where: { $0.id == c.id }),
           let same = customSchedules.first(where: { $0.name == c.name }) {
            return same.id
        }
        return c.id
    }

    func saveCustom(_ c: CustomSchedule, replacesCurrent: Bool = false) {
        var c = c
        c.id = resolvedCustomID(for: c)
        if let i = customSchedules.firstIndex(where: { $0.id == c.id }) {
            customSchedules[i] = c
        } else {
            customSchedules.append(c)
        }
        if replacesCurrent || data.customID == c.id {
            var d = data
            d.types = c.types
            d.cycle = c.cycle
            d.cycleStart = c.cycleStart ?? d.cycleStart
            d.templateName = c.name
            d.customID = c.id
            data = d
        } else {
            applyCustom(c)
        }
    }

    func setToday(isCycleDay index: Int) {
        data.setToday(isCycleDay: index)
        if let cid = data.customID, let i = customSchedules.firstIndex(where: { $0.id == cid }) {
            customSchedules[i].cycleStart = data.cycleStart
        }
    }

    func deleteCustom(id: UUID) {
        customSchedules.removeAll { $0.id == id }
        if data.customID == id { data.customID = nil }
    }

    func editableCurrent() -> CustomSchedule {
        var c: CustomSchedule
        if let id = data.customID, let saved = customSchedules.first(where: { $0.id == id }) {
            c = saved
        } else {
            c = CustomSchedule(name: data.displayTemplateName, types: data.types, cycle: data.cycle)
        }
        c.types = data.types
        c.cycle = data.cycle
        c.cycleStart = data.cycleStart
        return c
    }

    func importShared(_ imported: ScheduleData) {
        var new = imported
        new.copyReminderSettings(from: data)
        new.notes = data.notes
        data = new
    }

    func updateType(_ type: ShiftType) {
        guard let i = data.types.firstIndex(where: { $0.id == type.id }) else { return }
        data.types[i] = type
        if let cid = data.customID, let ci = customSchedules.firstIndex(where: { $0.id == cid }),
           let ti = customSchedules[ci].types.firstIndex(where: { $0.id == type.id }) {
            customSchedules[ci].types[ti] = type
        }
    }

    func addType() -> ShiftType {
        let used = Set(data.types.map(\.colorHex))
        let color = ShiftPalette.colors.first { !used.contains($0) } ?? ShiftPalette.colors[0]
        let t = ShiftType(name: String(localized: "新班次"), colorHex: color, startMinutes: 9 * 60, endMinutes: 18 * 60)
        data.types.append(t)
        return t
    }


    func enableWeather() async {
        if await WeatherProvider.shared.requestPermission() {
            WeatherCache.enabled = true
            weatherEnabled = true
            await refreshWeather(force: true)
        } else {
            alertMessage = String(localized: "定位权限没打开，天气用不了。可以到 iPhone 的「设置 > 班历 > 位置」里改成「使用 App 期间」。")
        }
    }

    func refreshWeather(force: Bool = false) async {
        guard !Self.isDemo, weatherEnabled else { return }
        weatherLoading = true
        defer { weatherLoading = false }
        let new = await WeatherProvider.shared.refreshIfNeeded(force: force)
        if new != weather {
            weather = new
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func refreshHolidays() async {
        guard !Self.isDemo, LocaleFeatures.current.showsChinaHolidays else { return }
        await Holidays.refreshIfNeeded()
        holidayVersion += 1
    }

    private static func demoWeather() -> WeatherSnapshot {
        let cal = Calendar.banli
        let start = cal.startOfDay(for: Date())
        let hours = (0..<48).map { i -> WeatherSnapshot.Hour in
            let d = cal.date(byAdding: .hour, value: i, to: start) ?? start
            let rainy = (22...26).contains(i)
            return WeatherSnapshot.Hour(date: d, temperature: 14 - abs(Double(i % 24) - 14) * 0.5,
                                        precipitationChance: rainy ? 0.7 : 0.1,
                                        symbol: rainy ? "cloud.rain.fill" : "cloud.sun.fill",
                                        condition: rainy ? String(localized: "小雨") : String(localized: "多云"))
        }
        let days = (0..<7).map { i -> WeatherSnapshot.Day in
            WeatherSnapshot.Day(date: cal.date(byAdding: .day, value: i, to: start) ?? start,
                                high: 16, low: 8, precipitationChance: i == 0 ? 0.6 : 0.2,
                                symbol: "cloud.sun.rain.fill", condition: String(localized: "多云转小雨"))
        }
        return WeatherSnapshot(hours: hours, days: days, fetchedAt: Date(), place: String(localized: "上海"),
                               markLightURL: nil, markDarkURL: nil, legalURL: nil)
    }


    func refreshReminders() {
        guard !Self.isDemo else { return }
        remindersDirty = true
        guard reminderTask == nil else { return }
        reminderTask = Task { [weak self] in
            guard let self else { return }
            defer { self.reminderTask = nil }
            while self.remindersDirty {
                self.remindersDirty = false
                let snapshot = self.data
                let pro = self.isPro
                let fallback = snapshot.alarmDelivery == .notification || !ShiftAlarmScheduler.isAuthorized
                let alarmError = await ShiftAlarmScheduler.reschedule(data: snapshot, active: pro)
                let notificationsOK = await ReminderScheduler.reschedule(data: snapshot, active: pro,
                                                                          includeShiftAlarms: fallback)
                let activityOK = await ShiftActivityManager.refresh(data: snapshot,
                                                                   active: pro && snapshot.liveActivityEnabled)
                await self.refreshReminderPermissions()
                if !self.remindersDirty {
                    if let alarmError {
                        self.reminderStatus = alarmError
                    } else if !notificationsOK {
                        self.reminderStatus = String(localized: "部分通知未能保存，请重试。")
                    } else if !activityOK {
                        self.reminderStatus = String(localized: "实时活动未能开启，请回到 App 后重试。")
                    } else { self.reminderStatus = nil }
                }
            }
        }
    }

    func refreshReminderPermissions() async {
        guard !Self.isDemo else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
        notificationsNeedPermission = settings.authorizationStatus == .notDetermined
        alarmsDenied = ShiftAlarmScheduler.isDenied
        alarmsNeedPermission = ShiftAlarmScheduler.needsPermission
        activitiesAllowed = ShiftActivityManager.isEnabled
    }

    func authorizeNotifications() async {
        guard isPro, !Self.isDemo else { return }
        _ = await ReminderScheduler.requestPermission()
        await refreshReminderPermissions()
        refreshReminders()
    }

    func authorizeShiftAlarms() async {
        guard isPro, !Self.isDemo else { return }
        if data.alarmDelivery == .alarm && ShiftAlarmScheduler.isAvailable {
            _ = await ShiftAlarmScheduler.requestPermission()
            await refreshReminderPermissions()
            refreshReminders()
        } else { await authorizeNotifications() }
    }


    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [AppConfig.proProductID]).first
    }

    func refreshEntitlements() async {
        guard !Self.isDemo else { return }
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               t.productID == AppConfig.proProductID,
               t.revocationDate == nil {
                owned = true
            }
        }
        isPro = Launch.isFree || owned
    }

    func purchase() async {
        await loadProduct()
        guard let product else {
            alertMessage = String(localized: "暂时连不上 App Store，请检查网络后再试。")
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    isPro = true
                } else {
                    alertMessage = String(localized: "购买验证没有通过，请稍后点「恢复购买」。")
                }
            case .pending:
                alertMessage = String(localized: "购买正在等待确认，完成后会自动解锁。")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            alertMessage = String(localized: "购买没有完成：\(error.localizedDescription)")
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            alertMessage = String(localized: "恢复失败：\(error.localizedDescription)")
            return
        }
        await refreshEntitlements()
        alertMessage = isPro ? String(localized: "已恢复高级版。") : String(localized: "这个 Apple 账号下没有找到购买记录。")
    }
}
