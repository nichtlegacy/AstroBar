import Foundation

/// Static facts about the Logitech-era ASTRO base stations (A50 X and A50 Gen 5)
/// and their wire protocol.
///
/// The protocol was reverse-engineered for the A50 Gen 5 by Sapd/HeadsetControl
/// (`lib/devices/logitech_astro_a50.hpp`). The A50 X answers the same frames on
/// the same vendor interface (usage page `0xFF32`, usage `0x74`, report id 2).
public enum A50X {
    /// Logitech's USB vendor id.
    public static let vendorID = 0x046D
    public static let a50XProductID = 0x0B0B
    public static let gen5ProductID = 0x0B1C
    public static let productIDs = [a50XProductID, gen5ProductID]

    /// The one vendor-defined HID collection both models expose; the other
    /// interfaces are audio and consumer controls.
    public static let vendorUsagePage = 0xFF32

    /// Reports are a fixed 64 bytes, report id included.
    public static let reportLength = 64

    /// The headset's master volume has 22 positions, like its wheel.
    public static let volumeRange = 0 ... 21

    /// Game/voice mix: 0 is all voice, 6 the centre, 12 all game.
    public static let chatMixRange = 0 ... 12

    /// Sidetone (how much of your own voice you hear): 0 is off, 6 the most.
    public static let sidetoneRange = 0 ... 6

    /// Brightness of the base station's light, in percent.
    public static let dockLightRange = 0 ... 100

    static let reportID: UInt8 = 0x02
    static let marker: UInt8 = 0x0C
    /// The length byte counts the three header bytes after it plus the payload.
    static let headerLength = 3

    public static func modelName(productID: Int) -> String {
        switch productID {
        case a50XProductID: "ASTRO A50 X"
        case gen5ProductID: "ASTRO A50 (Gen 5)"
        default: "ASTRO A50"
        }
    }
}

/// Command ids (byte 4 of a frame).
public enum A50XCommand: UInt8, Sendable {
    case battery = 0x06
    case volume = 0x08
    case sidetone = 0x09
    case chatMix = 0x0A
    case equalizer = 0x0D
    case dockLight = 0x0F
    case noiseGate = 0x14
}

/// Microphone noise gate. Only the values confirmed on hardware are named;
/// the device has further modes whose ids are not known yet.
public enum A50XNoiseGate: UInt8, CaseIterable, Sendable {
    case off = 0x00
    case night = 0x01
    case tournament = 0x04

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .night: "Night"
        case .tournament: "Tournament"
        }
    }
}

/// A decoded frame, whether it answers a request or was pushed by the device.
public struct A50XMessage: Equatable, Sendable {
    public var command: UInt8
    /// Echo token: the device returns the request's value, and uses 0 on pushes.
    public var handle: UInt8
    public var payload: [UInt8]

    public init(command: UInt8, handle: UInt8, payload: [UInt8]) {
        self.command = command
        self.handle = handle
        self.payload = payload
    }
}

/// Encoding and decoding of raw frames:
/// `[0x02, 0x0c, LEN, 0x00, CMD, HANDLE, payload…]`, zero-padded to 64 bytes.
public enum A50XFrame {
    /// Handle used for reads. Any value works; the device echoes it back.
    static let readHandle: UInt8 = 0x0C
    /// Handles G HUB uses for writes. The device only echoes them back.
    static let volumeSetHandle: UInt8 = 0x1B
    static let settingSetHandle: UInt8 = 0x1C
    static let noiseGateSetHandle: UInt8 = 0x2D

    public static func encode(command: UInt8, handle: UInt8, payload: [UInt8] = []) -> [UInt8] {
        var frame: [UInt8] = [
            A50X.reportID, A50X.marker, UInt8(A50X.headerLength + payload.count), 0x00, command, handle,
        ]
        frame.append(contentsOf: payload)
        if frame.count < A50X.reportLength {
            frame.append(contentsOf: [UInt8](repeating: 0, count: A50X.reportLength - frame.count))
        }
        return frame
    }

    /// Returns nil for anything that is not a well-formed frame.
    public static func decode(_ report: [UInt8]) -> A50XMessage? {
        guard report.count >= 6, report[0] == A50X.reportID, report[1] == A50X.marker else { return nil }
        let length = Int(report[2])
        guard length >= A50X.headerLength, 3 + length <= report.count else { return nil }
        return A50XMessage(command: report[4], handle: report[5], payload: Array(report[6 ..< 3 + length]))
    }
}

/// Meaning of the payloads. Pure functions so they can be tested against
/// frames captured from real hardware.
public enum A50XValue {
    /// Battery payload: `[percent, second reading, docked flag]`.
    public static func battery(_ payload: [UInt8]) -> (percent: Int, isDocked: Bool)? {
        guard let level = payload.first, level <= 100 else { return nil }
        let docked = payload.count >= 3 && payload[2] != 0
        return (Int(level), docked)
    }

    /// Volume payload: `[raw gain, 0, step]`. Only the step is understood.
    public static func volume(_ payload: [UInt8]) -> Int? {
        guard payload.count >= 3 else { return nil }
        let level = Int(payload[2])
        return A50X.volumeRange.contains(level) ? level : nil
    }

    /// Sidetone payload as read from an A50 X: `[01, 01, ff, level]`. The
    /// write payload is `[01, ff, level]`; the level is the last byte in both.
    public static func sidetone(_ payload: [UInt8]) -> Int? {
        guard payload.count >= 3, let last = payload.last else { return nil }
        let level = Int(last)
        return A50X.sidetoneRange.contains(level) ? level : nil
    }

    /// Dock light payload: `[brightness percent]`.
    public static func dockLight(_ payload: [UInt8]) -> Int? {
        guard let raw = payload.first else { return nil }
        let value = Int(raw)
        return A50X.dockLightRange.contains(value) ? value : nil
    }

    /// Noise gate payload: `[mode id]`. Returned raw, since not every mode
    /// the device can report has a known name.
    public static func noiseGate(_ payload: [UInt8]) -> UInt8? {
        payload.first
    }

    /// Chat mix payload: `[position]`.
    public static func chatMix(_ payload: [UInt8]) -> Int? {
        guard let raw = payload.first else { return nil }
        let value = Int(raw)
        return A50X.chatMixRange.contains(value) ? value : nil
    }
}
