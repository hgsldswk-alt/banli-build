import Foundation

enum BuiltInNames {
    static func localized(_ name: String) -> String {
        switch name {
        case "白班", "Day shift", "日班":
            return String(localized: "白班")
        case "夜班", "Night shift":
            return String(localized: "夜班")
        case "早班", "Early shift":
            return String(localized: "早班")
        case "中班", "Late shift":
            return String(localized: "中班")
        case "休息", "Off day":
            return String(localized: "休息")
        case "新班次", "New shift":
            return String(localized: "新班次")
        case "两班倒（白夜休休）", "12-Hour (Day·Night·Off·Off)", "兩班輪值（日夜休休）":
            return String(localized: "两班倒（白夜休休）")
        case "四班三倒", "4-Crew (2Early·2Late·2N·2Off)", "四班三輪（早早中中夜夜休休）":
            return String(localized: "四班三倒")
        case "三班倒（早中夜休）", "8-Hour (Early·Late·Night·Off)", "三班輪值（早中夜休）":
            return String(localized: "三班倒（早中夜休）")
        case "做一休一", "1 On, 1 Off":
            return String(localized: "做一休一")
        case "上二休二", "2 On, 2 Off", "做二休二":
            return String(localized: "上二休二")
        case "做六休一", "6 On, 1 Off":
            return String(localized: "做六休一")
        case "自定义", "Custom", "自訂":
            return String(localized: "自定义")
        case "元旦", "New Year's Day":
            return String(localized: "元旦")
        case "春节", "Lunar New Year", "春節":
            return String(localized: "春节")
        case "清明节", "Qingming Festival", "清明節":
            return String(localized: "清明节")
        case "劳动节", "Labor Day", "勞動節":
            return String(localized: "劳动节")
        case "端午节", "Dragon Boat Festival", "端午節":
            return String(localized: "端午节")
        case "中秋节", "Mid-Autumn Festival", "中秋節":
            return String(localized: "中秋节")
        case "国庆节", "National Day", "國慶節":
            return String(localized: "国庆节")
        default:
            return name
        }
    }
}
