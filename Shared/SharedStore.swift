import Foundation
import SwiftUI

enum AppConfig {
    static var appGroupID: String {
        Bundle.main.object(forInfoDictionaryKey: "BanLiAppGroup") as? String ?? "group.cn.banli.app"
    }

    static var appStoreURL: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "BanLiAppStoreID") as? String,
              !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }

    static var proProductID: String {
        Bundle.main.object(forInfoDictionaryKey: "BanLiProProductID") as? String ?? "cn.banli.app.pro"
    }
}

enum SharedStore {
    private static let dataKey = "scheduleData.v1"
    private static let proKey = "isPro"
    private static let onboardedKey = "hasOnboarded"
    private static let customKey = "customSchedules.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    static func load() -> ScheduleData {
        if let raw = defaults.data(forKey: dataKey),
           let data = try? JSONDecoder().decode(ScheduleData.self, from: raw) {
            return data
        }
        return ScheduleTemplate.all[0].makeData()
    }

    static func save(_ data: ScheduleData) {
        if let raw = try? JSONEncoder().encode(data) {
            defaults.set(raw, forKey: dataKey)
        }
    }

    static func loadCustom() -> [CustomSchedule] {
        guard let raw = defaults.data(forKey: customKey),
              let list = try? JSONDecoder().decode([CustomSchedule].self, from: raw) else { return [] }
        return list
    }

    static func saveCustom(_ list: [CustomSchedule]) {
        if let raw = try? JSONEncoder().encode(list) {
            defaults.set(raw, forKey: customKey)
        }
    }

    static var isPro: Bool {
        get { defaults.bool(forKey: proKey) }
        set { defaults.set(newValue, forKey: proKey) }
    }

    static var hasOnboarded: Bool {
        get { defaults.bool(forKey: onboardedKey) }
        set { defaults.set(newValue, forKey: onboardedKey) }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

extension ShiftType {
    var color: Color { Color(hex: colorHex) }

    var symbol: String {
        if isOff { return "cup.and.saucer.fill" }
        let h = (startMinutes / 60) % 24
        return (h >= 18 || h < 6) ? "moon.stars.fill" : "sun.max.fill"
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.72)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum ShiftPalette {
    static let colors = ["F2994A", "EB5757", "F2C94C", "27AE60", "2D9CDB",
                         "5B5FC7", "9B51E0", "E26DB0", "8D6E63", "9AA0A6"]
}
