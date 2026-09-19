import Foundation

/// Static facts about the Astro A50 Gen 4 base station and its wire protocol.
///
/// Reverse-engineered by tdryer/eh-fifty (https://github.com/tdryer/eh-fifty).
public enum A50 {
    /// USB vendor id, shared by all Astro Gaming devices.
    public static let vendorID = 0x9886

    /// Product id of the base station while the headset runs wirelessly through it.
    /// This is the revision that exposes the control HID interface.
    public static let baseStationProductID = 0x002C

    /// Product id seen when the headset is plugged in by USB cable directly.
    /// Pure USB-audio, no control interface — only charging happens here.
    public static let cableProductID = 0x002B

    /// Vendor-defined HID usage page of the control interface.
    public static let usagePage = 0xFF32

    /// Reports are a fixed 64 bytes.
    public static let reportLength = 64

    /// First byte of every request and response.
    static let magic: UInt8 = 0x02
}

/// Command bytes (the second byte of a request).
public enum A50Command: UInt8, Sendable {
    case getDeviceInfo = 0x03
    case getHeadsetStatus = 0x54
    case getBaseFirmwareMinor = 0x55
    case saveValues = 0x61
    case setSliderValue = 0x62
    case setEQPresetGain = 0x63
    case setNoiseGateMode = 0x64
    case setActiveEQPreset = 0x67
    case getSliderValue = 0x68
    case getEQPresetGain = 0x69
    case getNoiseGateMode = 0x6A
    case getActiveEQPreset = 0x6C
    case setEQPresetName = 0x6D
    case getEQPresetName = 0x6E
    case setEQPresetFreqAndBW = 0x6F
    case getEQPresetFreqAndBW = 0x70
    case setMicEQ = 0x71
    case getBalance = 0x72
    case setDefaultBalance = 0x73
    case setAlertVolume = 0x76
    case getDefaultBalance = 0x77
    /// Read-only: the documented set-command (`0x74`) has no observable effect.
    case getAutoShutoffTimer = 0x78
    case getAlertVolume = 0x7A
    case getMicEQ = 0x7B
    case getBatteryStatus = 0x7C
    case getHeadsetFirmwareMinor = 0xD6
    case getHeadsetFirmwareMajor = 0xDA
}

/// Response status, the second byte of a reply.
enum A50ResponseStatus: UInt8 {
    case noResponse = 0x00
    case error = 0x01
    case ok = 0x02
}

/// Errors surfaced by the transport / device layer.
public enum A50Error: Error, Equatable, LocalizedError, Sendable {
    case deviceNotConnected
    /// The headset is plugged in by cable (`0x002b`); control interface unavailable.
    case cableModeOnly
    case sendFailed(OSStatus)
    case timeout
    case malformedResponse
    /// The firmware refused the request. Gen 4 replies carry a numeric code and
    /// a NUL-terminated ASCII name such as `HID_ERROR_NO_EQ_WITH_THAT_VALUE`.
    case deviceError(code: Int, name: String?)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotConnected: "Astro A50 base station not found."
        case .cableModeOnly: "Headset is connected by USB cable. Use the base station for full control."
        case .sendFailed(let code): "Failed to send report to device (status \(code))."
        case .timeout: "The device did not respond in time."
        case .malformedResponse: "Received a malformed response from the device."
        case .deviceError(let code, let name):
            if let name { "The device rejected this request: \(name) (code \(code))." }
            else { "The device rejected this request (code \(code))." }
        case .invalidArgument(let detail): "Invalid argument: \(detail)."
        }
    }
}

// MARK: - Domain constants

public enum A50Limits {
    /// The three user EQ presets.
    public static let eqPresets = [1, 2, 3]
    /// The five EQ bands per preset.
    public static let eqBands = [1, 2, 3, 4, 5]
    /// Gain is stored offset by this amount (stored byte − offset = dB).
    public static let dbOffset = 12
    public static let minGain = -7
    public static let maxGain = 7
    public static let minCenterFreq = 80
    public static let maxCenterFreq = 15_000
    /// Bandwidth is stored as center-frequency × scale; valid range is 0.1…3.0.
    public static let bandwidthScale = 4096
    public static let minBandwidth = 409
    public static let maxBandwidth = 12_288
}
