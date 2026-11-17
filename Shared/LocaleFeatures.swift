import Foundation

struct LocaleFeatures {
    let language: String
    let region: String?

    static var current: LocaleFeatures {
        LocaleFeatures(language: Locale.preferredLanguages.first ?? "zh-Hans",
                       region: Locale.current.region?.identifier)
    }

    var showsLunar: Bool {
        Locale(identifier: language).language.languageCode?.identifier == "zh"
    }

    var showsChinaHolidays: Bool {
        guard showsLunar else { return false }
        let locale = Locale(identifier: language)
        let script = locale.language.script?.identifier
        let languageRegion = locale.region?.identifier
        let traditional = script == "Hant"
            || (script == nil && ["TW", "HK", "MO"].contains(languageRegion ?? ""))
        return region?.uppercased() == "CN" || !traditional
    }
}
