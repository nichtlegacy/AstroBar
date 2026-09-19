import Foundation
import Observation

/// How the status-bar item draws its icon.
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case headphones
    case battery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .headphones: "Headphones"
        case .battery: "Battery"
        }
    }
}

/// Persistent, observable user preferences (UserDefaults-backed).
@MainActor
@Observable
final class AppSettings {
    var showBatteryPercent: Bool {
        didSet { defaults.set(showBatteryPercent, forKey: Keys.showPercent) }
    }
    var iconStyle: MenuBarIconStyle {
        didSet { defaults.set(iconStyle.rawValue, forKey: Keys.iconStyle) }
    }
    var lowBatteryNotify: Bool {
        didSet { defaults.set(lowBatteryNotify, forKey: Keys.lowNotify) }
    }
    var lowBatteryThreshold: Int {
        didSet { defaults.set(lowBatteryThreshold, forKey: Keys.lowThreshold) }
    }

    /// Thresholds offered in Settings. Fine steps near empty, where the choice
    /// actually matters, and coarser ones above.
    static let lowBatteryThresholds = [5, 10, 15, 20, 25, 30, 40, 50]
    private let defaults: UserDefaults

    private enum Keys {
        static let showPercent = "showBatteryPercent"
        static let iconStyle = "menuBarIconStyle"
        static let lowNotify = "lowBatteryNotify"
        static let lowThreshold = "lowBatteryThreshold"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showBatteryPercent = defaults.object(forKey: Keys.showPercent) as? Bool ?? true
        self.iconStyle = (defaults.string(forKey: Keys.iconStyle))
            .flatMap(MenuBarIconStyle.init(rawValue:)) ?? .headphones
        self.lowBatteryNotify = defaults.bool(forKey: Keys.lowNotify)
        let storedThreshold = defaults.object(forKey: Keys.lowThreshold) as? Int ?? 15
        self.lowBatteryThreshold = Self.lowBatteryThresholds.contains(storedThreshold)
            ? storedThreshold
            : Self.lowBatteryThresholds.min(by: {
                abs($0 - storedThreshold) < abs($1 - storedThreshold)
            }) ?? 15
    }
}
