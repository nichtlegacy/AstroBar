import Foundation

/// What the app can offer for a connected headset family. The UI branches on
/// these instead of on the family itself, so a new family only has to declare
/// what it supports.
public struct DeviceCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Editable equalizer presets that can be switched from the status menu.
    public static let equalizerPresets = DeviceCapabilities(rawValue: 1 << 0)
    /// Live values must be persisted explicitly ("Save to headset").
    public static let saveToDevice = DeviceCapabilities(rawValue: 1 << 1)
    /// The Mac's volume keys can be routed to the headset's own volume.
    public static let volumeKeys = DeviceCapabilities(rawValue: 1 << 2)
}

/// The family of base station that is connected. Each family speaks its own
/// protocol and exposes its own set of controls.
public enum DeviceFamily: Sendable, Equatable {
    /// ASTRO A50 Gen 4 (`9886:002c`).
    case gen4
    /// ASTRO A50 X or A50 Gen 5, identified by their Logitech USB product id.
    case logitech(productID: Int)

    /// Name shown in the panel header and the status menu.
    public var modelName: String {
        switch self {
        case .gen4: "ASTRO A50"
        case let .logitech(productID): A50X.modelName(productID: productID)
        }
    }

    /// Title of the device section in Settings.
    public var settingsTitle: String {
        switch self {
        case .gen4: "Astro A50 (Gen 4)"
        case let .logitech(productID): A50X.modelName(productID: productID)
        }
    }

    public var capabilities: DeviceCapabilities {
        switch self {
        case .gen4: [.equalizerPresets, .saveToDevice]
        case .logitech: [.volumeKeys]
        }
    }
}

/// CoreAudio's `kAudioDevicePropertyModelUID` for USB audio devices.
public enum AudioModelUID {
    /// Splits `"<name>:<VID>:<PID>"` (hex, for example `Astro A50 Game:9886:002C`)
    /// into its USB ids. Nil for anything that does not end in two hex fields.
    public static func parse(_ modelUID: String) -> (vendorID: Int, productID: Int)? {
        let parts = modelUID.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let vendorID = Int(parts[parts.count - 2], radix: 16),
              let productID = Int(parts[parts.count - 1], radix: 16) else { return nil }
        return (vendorID, productID)
    }

    /// True when the model UID names one of the A50 X / A50 Gen 5 base stations.
    public static func isLogitechA50(_ modelUID: String) -> Bool {
        guard let ids = parse(modelUID) else { return false }
        return ids.vendorID == A50X.vendorID && A50X.productIDs.contains(ids.productID)
    }
}
