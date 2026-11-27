import Foundation

enum Launch {
    static let freePeriod = false
    static var isFree: Bool {
        guard freePeriod else { return false }
        let args = ProcessInfo.processInfo.arguments
        return !(args.contains("-paywall") || args.contains("-free") || args.contains("-paid-mode"))
    }
}
