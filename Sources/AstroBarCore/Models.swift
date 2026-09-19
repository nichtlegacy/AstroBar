import Foundation

/// Headset battery state.
public struct BatteryStatus: Equatable, Sendable {
    public var isCharging: Bool
    /// 0…100, as reported (bits 0-6 of the status byte).
    public var chargePercent: Int

    public init(isCharging: Bool, chargePercent: Int) {
        self.isCharging = isCharging
        self.chargePercent = chargePercent
    }

    /// Decode from the raw battery status byte (`0x7C`).
    ///
    /// The percent field is seven bits wide, so it can carry values the battery
    /// cannot actually reach; anything above 100 is a bad frame and is clamped.
    init(rawByte: UInt8) {
        self.isCharging = (rawByte & 0x80) != 0
        self.chargePercent = min(100, Int(rawByte & 0x7F))
    }
}

/// Power / dock state of the headset.
public struct HeadsetStatus: Equatable, Sendable {
    /// True while the base station has a live radio link to the headset.
    ///
    /// This doubles as "the headset is on": the link drops when it powers off
    /// or goes out of range. It matters because the base keeps answering with
    /// the *last known* battery level after the link is gone — so a reading is
    /// only current while this is true.
    public var isLinked: Bool
    public var isDocked: Bool

    public init(isLinked: Bool, isDocked: Bool) {
        self.isLinked = isLinked
        self.isDocked = isDocked
    }

    init(rawByte: UInt8) {
        self.isDocked = (rawByte & 0x01) != 0
        self.isLinked = (rawByte & 0x02) != 0
    }
}

/// Gain (dB) for each of the five bands of an EQ preset.
public struct EQPresetGain: Equatable, Sendable {
    /// Currently active gains, one per band, in dB (-7…7).
    public var gain: [Int]
    /// Gains persisted to the device (what survives a power cycle).
    public var savedGain: [Int]

    public init(gain: [Int], savedGain: [Int]) {
        self.gain = gain
        self.savedGain = savedGain
    }
}

/// Center frequency + bandwidth of a single EQ band.
public struct EQPresetBand: Equatable, Sendable {
    public var bandwidth: Int
    public var savedBandwidth: Int
    public var centerFreq: Int
    public var savedCenterFreq: Int

    public init(bandwidth: Int, savedBandwidth: Int, centerFreq: Int, savedCenterFreq: Int) {
        self.bandwidth = bandwidth
        self.savedBandwidth = savedBandwidth
        self.centerFreq = centerFreq
        self.savedCenterFreq = savedCenterFreq
    }
}

/// The mix sliders on the base station / stream port.
public enum SliderType: UInt8, CaseIterable, Sendable {
    case streamMixMic = 0x00
    case streamMixChat = 0x01
    case streamMixGame = 0x02
    case streamMixAux = 0x03
    case mic = 0x04
    case sideTone = 0x05

    public var displayName: String {
        switch self {
        case .streamMixMic: "Stream · Mic"
        case .streamMixChat: "Stream · Chat"
        case .streamMixGame: "Stream · Game"
        case .streamMixAux: "Stream · Aux"
        case .mic: "Microphone"
        case .sideTone: "Side Tone"
        }
    }
}

/// Microphone noise gate mode.
public enum NoiseGateMode: UInt8, CaseIterable, Sendable {
    case streaming = 0x00
    case night = 0x01
    case home = 0x02
    case tournament = 0x03

    public var displayName: String {
        switch self {
        case .streaming: "Streaming"
        case .night: "Night"
        case .home: "Home"
        case .tournament: "Tournament"
        }
    }
}

/// Firmware version, formatted `major.minor` like Astro Command Center.
public struct FirmwareVersion: Equatable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }
    public var description: String { "\(major).\(minor)" }
}

/// USB identity reported by the base station.
public struct DeviceInfo: Equatable, Sendable, CustomStringConvertible {
    public var vendorID: Int
    public var productID: Int
    public init(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
    }
    public var description: String {
        String(format: "%04x:%04x", vendorID, productID)
    }
}

/// Balance between game and chat audio (0 = 100% game … 255 = 100% chat).
public struct Balance: Equatable, Sendable {
    public var raw: Int
    public init(raw: Int) { self.raw = raw }

    /// 0.0 = full game, 1.0 = full chat.
    public var chatFraction: Double { Double(raw) / 255.0 }
}
