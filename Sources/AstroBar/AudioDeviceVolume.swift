import CoreAudio
import Foundation

/// Reads and sets the macOS output volume of the Astro A50 audio device via
/// CoreAudio. This is the system mixer level, independent of the HID protocol.
enum AudioDeviceVolume {
    /// Find the A50 output device.
    ///
    /// Prefers the stable USB device UID (AppleUSBAudioEngine UIDs embed the
    /// vendor/product ids) over the user-visible name, which varies with
    /// firmware and locale. Among the A50's Game/Chat pair, the Game device
    /// is the main output.
    static func a50OutputDevice() -> AudioDeviceID? {
        guard let devices = allOutputDevices() else { return nil }
        let candidates = devices.compactMap { device -> (id: AudioDeviceID, uid: String, name: String)? in
            guard let uid = uid(of: device), let name = name(of: device) else { return nil }
            return (device, uid, name)
        }
        // USB vendor id 0x9886 appears in the UID string for Astro devices.
        let astro = candidates.filter { $0.uid.localizedCaseInsensitiveContains("9886") }
        let pool = astro.isEmpty ? candidates.filter { $0.name.localizedCaseInsensitiveContains("A50") } : astro
        return pool.first { $0.name.localizedCaseInsensitiveContains("Game") }?.id
            ?? pool.first?.id
    }

    static func volume(of device: AudioDeviceID) -> Float? {
        // Try the master element first, then average the channels.
        if let v = scalar(device, channel: kAudioObjectPropertyElementMain) { return v }
        let left = scalar(device, channel: 1)
        let right = scalar(device, channel: 2)
        switch (left, right) {
        case let (l?, r?): return (l + r) / 2
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    static func setVolume(_ value: Float, of device: AudioDeviceID) {
        let clamped = max(0, min(1, value))
        if setScalar(clamped, device, channel: kAudioObjectPropertyElementMain) { return }
        _ = setScalar(clamped, device, channel: 1)
        _ = setScalar(clamped, device, channel: 2)
    }

    // MARK: - Private

    private static func scalar(_ device: AudioDeviceID, channel: AudioObjectPropertyElement) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: channel)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    @discardableResult
    private static func setScalar(_ value: Float, _ device: AudioDeviceID, channel: AudioObjectPropertyElement) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: channel)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var newValue = Float32(value)
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &newValue)
        return status == noErr
    }

    /// All audio devices that expose output streams.
    private static func allOutputDevices() -> [AudioDeviceID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return nil }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices) == noErr else { return nil }
        return devices.filter(hasOutputStreams)
    }

    private static func uid(of device: AudioDeviceID) -> String? {
        stringProperty(kAudioDevicePropertyDeviceUID, of: device)
    }

    private static func name(of device: AudioDeviceID) -> String? {
        stringProperty(kAudioObjectPropertyName, of: device)
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        return status == noErr ? (value as String) : nil
    }

    private static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }
}
