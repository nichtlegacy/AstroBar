import AstroBarCore
import SwiftUI

/// What the headset is doing right now, folded from the three separate signals
/// the hardware exposes: the connection mode, the dock/power bits, and the
/// charging flag in the battery byte.
///
/// These overlap — a docked headset can be on or off, and a headset on the
/// charging cable reports nothing at all — so the panel shows one resolved
/// state instead of a row of chips the user has to combine in their head.
enum HeadsetPowerState: Equatable {
    /// Powered on and running off its own battery.
    case inUse
    /// Powered on and linked, charging over its cable while still in use.
    case chargingInUse
    /// On the base station, taking charge.
    case chargingOnBase
    /// On the base station, battery full.
    case chargedOnBase
    /// Powered off (whether or not it sits on the base).
    case off
    /// Plugged into the USB charging cable: charges, reports no values.
    case chargingOverCable
    /// No base station, or it hasn't answered yet.
    case unknown

    /// Resolves the state from everything the monitor knows.
    static func resolve(
        status: ConnectionStatus,
        headset: HeadsetStatus?,
        battery: BatteryStatus?
    ) -> HeadsetPowerState {
        if status == .cableMode { return .chargingOverCable }
        guard status == .connected, let headset else { return .unknown }

        if headset.isDocked {
            // A docked headset that stopped charging has finished charging; the
            // on/off bit is irrelevant while it sits on the base.
            return battery?.isCharging == true ? .chargingOnBase : .chargedOnBase
        }
        guard headset.isLinked else { return .off }

        // Off the base but still charging: plugged into its own cable while the
        // radio link to the base station stays up.
        return battery?.isCharging == true ? .chargingInUse : .inUse
    }

    /// Which rate the estimator should be learning right now, or nil when there
    /// is nothing meaningful to measure.
    var batteryProfile: BatteryProfile? {
        switch self {
        case .inUse: .discharging
        case .chargingOnBase: .chargingOnBase
        case .chargingInUse: .chargingInUse
        // Full, off, or reporting nothing: no movement to measure.
        case .chargedOnBase, .off, .chargingOverCable, .unknown: nil
        }
    }

    var label: String {
        switch self {
        case .inUse: "In use"
        case .chargingInUse: "Charging"
        case .chargingOnBase: "Charging"
        case .chargedOnBase: "Charged"
        case .off: "Off"
        case .chargingOverCable: "Charging"
        case .unknown: "—"
        }
    }

    var systemImage: String {
        switch self {
        case .inUse: "headphones"
        case .chargingInUse: "bolt.fill"
        case .chargingOnBase: "bolt.fill"
        case .chargedOnBase: "checkmark.circle.fill"
        case .off: "powersleep"
        case .chargingOverCable: "bolt.fill"
        case .unknown: "questionmark"
        }
    }

    var tint: Color {
        switch self {
        case .inUse: .accentColor
        case .chargingOnBase, .chargingInUse, .chargingOverCable: .green
        case .chargedOnBase: .green
        case .off, .unknown: .secondary
        }
    }

    /// Where the headset is sitting, shown under the model name.
    func placement(status: ConnectionStatus) -> String {
        switch status {
        case .connected:
            switch self {
            case .chargingOnBase, .chargedOnBase: "Base Station · Docked"
            default: "Base Station · Wireless"
            }
        case .cableMode: "USB Cable"
        case .scanning: "Searching for base station…"
        case .disconnected: "Not connected"
        }
    }

    /// Only a headset running on its own battery has a runtime worth showing.
    var showsRuntime: Bool { self == .inUse }

    /// True while the headset is taking charge through the base or its cable.
    var isCharging: Bool {
        self == .chargingOnBase || self == .chargingInUse || self == .chargingOverCable
    }
}
