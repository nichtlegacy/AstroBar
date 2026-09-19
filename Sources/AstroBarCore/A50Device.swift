import Foundation

/// High-level, typed access to the Astro A50 base station.
///
/// Wraps `HIDTransport`. All requests are serialized on a private queue so only
/// one request/response exchange is ever in flight (the protocol is strictly
/// request/response with no tags).
public actor A50Device {
    private let transport: HIDTransport
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "de.nichtlegacy.astrobar.hid.requests")
    private var started = false

    public init(transport: HIDTransport = HIDTransport(), timeout: TimeInterval = 3.0) {
        self.transport = transport
        self.timeout = timeout
    }

    public func start() {
        guard !started else { return }
        started = true
        transport.start()
    }

    public func stop() {
        transport.stop()
        started = false
    }

    public nonisolated var isConnected: Bool { transport.isConnected }

    public nonisolated func setConnectionChangeHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        transport.onConnectionChange = handler
    }

    private func validatedPreset(_ preset: Int) throws -> UInt8 {
        guard A50Limits.eqPresets.contains(preset) else {
            throw A50Error.invalidArgument("preset must be one of \(A50Limits.eqPresets.map(String.init).joined(separator: ", "))")
        }
        return UInt8(preset)
    }

    private func validatedBand(_ band: Int) throws -> UInt8 {
        guard A50Limits.eqBands.contains(band) else {
            throw A50Error.invalidArgument("band must be one of \(A50Limits.eqBands.map(String.init).joined(separator: ", "))")
        }
        return UInt8(band)
    }

    // MARK: - Core request

    /// `atLeast` is how many data bytes the caller needs. The firmware's length
    /// field is not reliable, so stating the expectation keeps a short reply
    /// from truncating an answer that actually arrived in full.
    private func raw(
        _ command: A50Command,
        _ payload: [UInt8] = [],
        atLeast minimum: Int = 0
    ) async throws -> [UInt8] {
        try A50Frame.parse(
            try await dispatch(A50Frame.encode(command: command, payload: payload)),
            atLeast: minimum)
    }

    /// Sends a request and returns the untouched reply, framing bytes included.
    /// For diagnostics — everything else goes through `raw`.
    public func rawExchange(command: A50Command, payload: [UInt8] = []) async throws -> [UInt8] {
        try await dispatch(A50Frame.encode(command: command, payload: payload))
    }

    private func dispatch(_ bytes: [UInt8]) async throws -> [UInt8] {
        let transport = self.transport
        let timeout = self.timeout
        let queue = self.queue
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try transport.request(bytes, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Status (read)

    public func batteryStatus() async throws -> BatteryStatus {
        let data = try await raw(.getBatteryStatus, atLeast: 1)
        guard let byte = data.first else { throw A50Error.malformedResponse }
        return BatteryStatus(rawByte: byte)
    }

    public func headsetStatus() async throws -> HeadsetStatus {
        let data = try await raw(.getHeadsetStatus, atLeast: 1)
        guard let byte = data.first else { throw A50Error.malformedResponse }
        return HeadsetStatus(rawByte: byte)
    }

    // MARK: - Equalizer

    public func activeEQPreset() async throws -> Int {
        let data = try await raw(.getActiveEQPreset, atLeast: 1)
        guard let byte = data.first else { throw A50Error.malformedResponse }
        return Int(byte)
    }

    /// Selects the active preset and waits for the device to actually report it.
    ///
    /// The firmware acknowledges the write immediately but applies it a moment
    /// later, so an unconditional read straight afterwards still returns the old
    /// preset. Returns once the read-back agrees, or after the poll budget runs
    /// out — the write itself has already been accepted either way.
    public func setActiveEQPreset(_ preset: Int) async throws {
        let target = try validatedPreset(preset)
        _ = try await raw(.setActiveEQPreset, [target])

        for _ in 0 ..< Self.readBackAttempts {
            try await Task.sleep(for: .milliseconds(Self.readBackInterval))
            if let current = try? await activeEQPreset(), current == Int(target) { return }
        }
    }

    /// Poll budget for values the firmware applies asynchronously.
    private static let readBackAttempts = 8
    private static let readBackInterval = 200

    public func eqPresetGain(_ preset: Int) async throws -> EQPresetGain {
        let data = try await raw(.getEQPresetGain, [try validatedPreset(preset)], atLeast: 12)
        guard data.count >= 12 else { throw A50Error.malformedResponse }
        // [cmd, preset, active×5, saved×5]
        let active = data[2 ..< 7].map { Int($0) - A50Limits.dbOffset }
        let saved = data[7 ..< 12].map { Int($0) - A50Limits.dbOffset }
        return EQPresetGain(gain: active, savedGain: saved)
    }

    public func setEQPresetGain(_ preset: Int, gain: [Int]) async throws {
        let validatedPreset = try validatedPreset(preset)
        guard gain.count == A50Limits.eqBands.count else {
            throw A50Error.invalidArgument("gain must contain \(A50Limits.eqBands.count) bands")
        }
        let clamped = gain.map { max(A50Limits.minGain, min(A50Limits.maxGain, $0)) }
        let payload = [validatedPreset] + clamped.map { UInt8($0 + A50Limits.dbOffset) }
        _ = try await raw(.setEQPresetGain, payload)
    }

    public func eqPresetName(_ preset: Int, saved: Bool = false) async throws -> String {
        let data = try await raw(.getEQPresetName, [try validatedPreset(preset), saved ? 1 : 0], atLeast: 3)
        guard data.count > 2 else { throw A50Error.malformedResponse }
        let nameBytes = data[2...].prefix { $0 != 0 }
        return String(decoding: nameBytes, as: UTF8.self)
    }

    public func setEQPresetName(_ preset: Int, name: String) async throws {
        let validatedPreset = try validatedPreset(preset)
        let encoded = Array(name.utf8) + [0]
        let payload = [validatedPreset, UInt8(encoded.count)] + encoded
        _ = try await raw(.setEQPresetName, payload)
    }

    public func eqPresetBand(_ preset: Int, band: Int) async throws -> EQPresetBand {
        let data = try await raw(.getEQPresetFreqAndBW, [try validatedPreset(preset), try validatedBand(band)], atLeast: 11)
        guard data.count >= 11 else { throw A50Error.malformedResponse }
        // [cmd, preset, band, bw, savedBw, center, savedCenter] (uint16 LE each)
        func u16(_ i: Int) -> Int { Int(data[i]) | (Int(data[i + 1]) << 8) }
        return EQPresetBand(
            bandwidth: u16(3),
            savedBandwidth: u16(5),
            centerFreq: u16(7),
            savedCenterFreq: u16(9))
    }

    public func setEQPresetBand(_ preset: Int, band: Int, centerFreq: Int, bandwidth: Int) async throws {
        let validatedPreset = try validatedPreset(preset)
        let validatedBand = try validatedBand(band)
        let freq = max(A50Limits.minCenterFreq, min(A50Limits.maxCenterFreq, centerFreq))
        // The outermost bands (shelves) carry no bandwidth. The firmware range-
        // checks the centre frequency but stores any bandwidth it is handed, so
        // that one has to be clamped here.
        let bw = (band == 1 || band == 5)
            ? 0
            : max(A50Limits.minBandwidth, min(A50Limits.maxBandwidth, bandwidth))
        func le(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }
        let payload = [validatedPreset, validatedBand] + le(bw) + le(freq)
        _ = try await raw(.setEQPresetFreqAndBW, payload)
    }

    // MARK: - Mix sliders / balance

    public func sliderValue(_ slider: SliderType, saved: Bool = false) async throws -> Int {
        let data = try await raw(.getSliderValue, [slider.rawValue], atLeast: 4)
        guard data.count >= 4 else { throw A50Error.malformedResponse }
        return Int(data[saved ? 3 : 2])
    }

    public func setSliderValue(_ slider: SliderType, percent: Int) async throws {
        let clamped = max(0, min(100, percent))
        _ = try await raw(.setSliderValue, [slider.rawValue, UInt8(clamped)])
    }

    public func balance() async throws -> Balance {
        let data = try await raw(.getBalance, atLeast: 1)
        guard let byte = data.first else { throw A50Error.malformedResponse }
        return Balance(raw: Int(byte))
    }

    public func defaultBalance(saved: Bool = false) async throws -> Balance {
        let data = try await raw(.getDefaultBalance, [saved ? 1 : 0], atLeast: 1)
        guard let byte = data.first else { throw A50Error.malformedResponse }
        return Balance(raw: Int(byte))
    }

    public func setDefaultBalance(_ raw: Int) async throws {
        let clamped = max(0, min(255, raw))
        _ = try await self.raw(.setDefaultBalance, [UInt8(clamped)])
    }

    /// Auto-shutoff timer as stored on the device (unit is undocumented in the
    /// protocol research; setting it is ignored by the firmware, so read-only).
    public func autoShutoffTimer() async throws -> Int {
        let data = try await raw(.getAutoShutoffTimer, atLeast: 1)
        guard let byte = data.first else { throw A50Error.malformedResponse }
        return Int(byte)
    }

    // MARK: - Microphone

    public func alertVolume(saved: Bool = false) async throws -> Int {
        let data = try await raw(.getAlertVolume, [saved ? 1 : 0], atLeast: 1)
        guard let byte = data.first else { throw A50Error.malformedResponse }
        return Int(byte)
    }

    public func setAlertVolume(_ percent: Int) async throws {
        let clamped = max(0, min(100, percent))
        _ = try await raw(.setAlertVolume, [UInt8(clamped)])
    }

    public func micEQ(saved: Bool = false) async throws -> Int {
        let data = try await raw(.getMicEQ, [saved ? 1 : 0], atLeast: 1)
        guard let byte = data.first else { throw A50Error.malformedResponse }
        return Int(byte)
    }

    public func setMicEQ(_ preset: Int) async throws {
        _ = try await raw(.setMicEQ, [UInt8(max(0, min(2, preset)))])
    }

    public func noiseGateMode(saved: Bool = false) async throws -> NoiseGateMode {
        let data = try await raw(.getNoiseGateMode, atLeast: 3)
        guard data.count >= 3 else { throw A50Error.malformedResponse }
        return NoiseGateMode(rawValue: data[saved ? 2 : 1]) ?? .streaming
    }

    public func setNoiseGateMode(_ mode: NoiseGateMode) async throws {
        _ = try await raw(.setNoiseGateMode, [mode.rawValue])
    }

    // MARK: - Device info

    public func deviceInfo() async throws -> DeviceInfo {
        let data = try await raw(.getDeviceInfo, atLeast: 8)
        guard data.count >= 8 else { throw A50Error.malformedResponse }
        let vendor = Int(data[4]) | (Int(data[5]) << 8)
        let product = Int(data[6]) | (Int(data[7]) << 8)
        return DeviceInfo(vendorID: vendor, productID: product)
    }

    public func baseFirmwareVersion() async throws -> FirmwareVersion {
        let info = try await raw(.getDeviceInfo, atLeast: 25)
        guard info.count >= 25 else { throw A50Error.malformedResponse }
        let minor = try await raw(.getBaseFirmwareMinor, atLeast: 1)
        guard let minorByte = minor.first else { throw A50Error.malformedResponse }
        let major = Int(info[21]) | (Int(info[22]) << 8) | (Int(info[23]) << 16) | (Int(info[24]) << 24)
        return FirmwareVersion(major: major, minor: Int(minorByte))
    }

    public func headsetFirmwareVersion() async throws -> FirmwareVersion {
        let major = try await raw(.getHeadsetFirmwareMajor, [0x0A], atLeast: 4)
        guard major.count >= 4 else { throw A50Error.malformedResponse }
        let minor = try await raw(.getHeadsetFirmwareMinor, [0x0A], atLeast: 1)
        guard let minorByte = minor.first else { throw A50Error.malformedResponse }
        let majorValue = Int(major[0]) | (Int(major[1]) << 8) | (Int(major[2]) << 16) | (Int(major[3]) << 24)
        return FirmwareVersion(major: majorValue, minor: Int(minorByte))
    }

    // MARK: - Persistence

    /// Persist active values to the device so they survive a power cycle.
    /// Can take ~2 seconds to respond.
    public func save() async throws {
        _ = try await raw(.saveValues)
    }
}
