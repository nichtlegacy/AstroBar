import AstroBarCore
import Foundation
import Observation
import SwiftUI

/// Connection state shown in the UI.
enum ConnectionStatus: Equatable {
    case scanning
    case connected
    case cableMode
    case disconnected
}

/// The app's single source of truth. Owns the `A50Device`, polls live values,
/// and applies user edits optimistically.
@MainActor
@Observable
final class A50Monitor {
    // Connection
    private(set) var status: ConnectionStatus = .scanning
    private(set) var lastError: String?

    // Live power state
    private(set) var battery: BatteryStatus?
    private(set) var headset: HeadsetStatus?

    // Equalizer
    var activePreset: Int = 1
    private(set) var presetNames: [Int: String] = [:]
    private(set) var presetGains: [Int: EQPresetGain] = [:]
    /// Per-band frequency/bandwidth, keyed by preset (lazily loaded).
    private(set) var presetBands: [Int: [EQPresetBand]] = [:]

    // Mix sliders
    private(set) var sliders: [SliderType: Int] = [:]

    // Audio
    var balanceRaw: Int = 128
    var alertVolume: Int = 0

    // Microphone
    var micEQ: Int = 0
    var noiseGate: NoiseGateMode = .streaming

    // System output volume (CoreAudio, not HID)
    var systemVolume: Double = 0
    private(set) var hasAudioDevice = false

    /// How long the charge will last, or how long it still needs to fill up,
    /// estimated from the observed rate. Nil until enough has been measured.
    private(set) var batteryProjection: BatteryEstimator.Projection?

    /// Resolved power state shown in the panel header.
    var powerState: HeadsetPowerState {
        HeadsetPowerState.resolve(status: status, headset: headset, battery: battery)
    }

    /// True when the reported charge is the last value the base saw rather than
    /// a current one: with the headset off the radio link and off the base, the
    /// base keeps answering with whatever it remembers.
    var batteryIsStale: Bool {
        guard let headset else { return false }
        return !headset.isLinked && !headset.isDocked
    }

    // Info
    private(set) var deviceInfo: DeviceInfo?
    private(set) var baseFirmware: FirmwareVersion?
    private(set) var headsetFirmware: FirmwareVersion?
    private(set) var autoShutoffTimer: Int?

    /// User preferences (set by AppDelegate); drives the low-battery alert.
    var settings: AppSettings?

    private let device = A50Device()
    private var pollTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var started = false
    private var lowBatteryAlarm = LowBatteryAlarm(threshold: 15)
    private var batteryEstimator = BatteryEstimator(store: .userDefaults())

    /// Populate with representative data for offline UI rendering/previews.
    #if DEBUG
    func seedPreview() {
        status = .connected
        battery = BatteryStatus(isCharging: false, chargePercent: 54)
        headset = HeadsetStatus(isLinked: true, isDocked: false)
        presetNames = [1: "LEGACY", 2: "PRO", 3: "ASTRO"]
        presetGains = [
            1: EQPresetGain(gain: [-1, -2, -1, 3, 0], savedGain: [-1, -2, -1, 3, 0]),
            2: EQPresetGain(gain: [-5, 7, -5, 6, 1], savedGain: [-5, 7, -5, 6, 1]),
            3: EQPresetGain(gain: [5, -4, 5, -5, 4], savedGain: [5, -4, 5, -5, 4]),
        ]
        presetBands = [1: [
            EQPresetBand(bandwidth: 0, savedBandwidth: 0, centerFreq: 90, savedCenterFreq: 90),
            EQPresetBand(bandwidth: 8192, savedBandwidth: 8192, centerFreq: 406, savedCenterFreq: 406),
            EQPresetBand(bandwidth: 8192, savedBandwidth: 8192, centerFreq: 783, savedCenterFreq: 783),
            EQPresetBand(bandwidth: 8192, savedBandwidth: 8192, centerFreq: 4001, savedCenterFreq: 4001),
            EQPresetBand(bandwidth: 0, savedBandwidth: 0, centerFreq: 7001, savedCenterFreq: 7001),
        ]]
        sliders = [.streamMixMic: 0, .streamMixChat: 81, .streamMixGame: 68, .streamMixAux: 0, .mic: 100, .sideTone: 0]
        balanceRaw = 255
        alertVolume = 0
        micEQ = 2
        noiseGate = .home
        deviceInfo = DeviceInfo(vendorID: 0x9886, productID: 0x002C)
        baseFirmware = FirmwareVersion(major: 40372, minor: 43)
        headsetFirmware = FirmwareVersion(major: 39964, minor: 43)
        batteryProjection = .untilEmpty(5 * 3600 + 20 * 60)
    }
    #endif

    func gains(for preset: Int) -> [Int] {
        presetGains[preset]?.gain ?? [0, 0, 0, 0, 0]
    }

    func name(for preset: Int) -> String {
        presetNames[preset] ?? "Preset \(preset)"
    }

    func bands(for preset: Int) -> [EQPresetBand] {
        presetBands[preset] ?? []
    }

    /// Snapshot of a slot in the shape the export format uses.
    func template(for preset: Int) -> EQTemplate {
        EQTemplate(
            name: name(for: preset),
            gain: gains(for: preset),
            bands: bands(for: preset).map {
                EQTemplate.Band(centerFreq: $0.centerFreq, bandwidth: $0.bandwidth)
            })
    }

    /// Writes a whole preset — name, gains, and every band — into one slot.
    ///
    /// The slot is updated locally first so the panel reflects the choice at
    /// once; the values are re-read afterwards so anything the firmware clamped
    /// shows up as what the device actually stored.
    func apply(_ template: EQTemplate, to preset: Int, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard template.isWellFormed else {
            lastError = "That preset does not have five bands."
            completion?(false)
            return
        }

        presetNames[preset] = template.name
        presetGains[preset] = EQPresetGain(
            gain: template.gain,
            savedGain: presetGains[preset]?.savedGain ?? template.gain)
        presetBands[preset] = template.bands.map {
            EQPresetBand(
                bandwidth: $0.bandwidth, savedBandwidth: $0.bandwidth,
                centerFreq: $0.centerFreq, savedCenterFreq: $0.centerFreq)
        }

        write({
            try await self.device.setEQPresetName(preset, name: template.name)
            try await self.device.setEQPresetGain(preset, gain: template.gain)
            for (index, band) in template.bands.enumerated() {
                try await self.device.setEQPresetBand(
                    preset, band: index + 1,
                    centerFreq: band.centerFreq, bandwidth: band.bandwidth)
            }
        }, completion: { [weak self] succeeded in
            if succeeded { self?.reloadPreset(preset) }
            completion?(succeeded)
        })
    }

    /// Re-reads one slot after a bulk write.
    private func reloadPreset(_ preset: Int) {
        Task {
            presetNames[preset] = (try? await device.eqPresetName(preset)) ?? presetNames[preset]
            presetGains[preset] = (try? await device.eqPresetGain(preset)) ?? presetGains[preset]
            await loadBands(preset)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        device.setConnectionChangeHandler { [weak self] connected in
            Task { @MainActor in
                await self?.handleConnectionChange(connected)
            }
        }
        Task { await device.start() }
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    private func handleConnectionChange(_ connected: Bool) async {
        if connected {
            status = .connected
            lastError = nil
            loadAll()
        } else {
            await refreshDisconnectedStatus()
        }
    }

    private func tick() async {
        if device.isConnected {
            await refreshDynamic()
        } else {
            await refreshDisconnectedStatus()
        }
    }

    private func refreshDisconnectedStatus() async {
        if USBPresence.cableModeConnected() {
            status = .cableMode
        } else if status != .scanning || battery != nil {
            status = .disconnected
        }
        battery = nil
        headset = nil
        batteryProjection = nil
        batteryEstimator.reset()
    }

    // MARK: - Reads

    /// Cheap values that change at runtime.
    func refreshDynamic() async {
        do {
            battery = try await device.batteryStatus()
            headset = try await device.headsetStatus()
            if status != .connected { status = .connected }
        } catch {
            note(error)
        }
        refreshVolume()
        checkLowBattery()
        updateBatteryProjection()
    }

    /// Feeds the latest reading to the estimator and republishes the result.
    ///
    /// A stale reading must not reach the estimator: it would sit at a fixed
    /// percentage for as long as the headset is off and then jump when it comes
    /// back, which reads as an enormous change over that whole gap.
    private func updateBatteryProjection() {
        guard let battery, !batteryIsStale, let profile = powerState.batteryProfile else {
            batteryProjection = nil
            batteryEstimator.record(percent: battery?.chargePercent ?? 0, profile: nil)
            return
        }
        batteryEstimator.record(percent: battery.chargePercent, profile: profile)
        batteryProjection = batteryEstimator.projection(
            percent: battery.chargePercent, profile: profile)
    }

    /// Fire a one-shot notification when the battery crosses below the
    /// configured threshold (re-arms once it recovers or starts charging).
    private func checkLowBattery() {
        guard let settings, settings.lowBatteryNotify, let battery, !batteryIsStale else { return }
        if lowBatteryAlarm.threshold != settings.lowBatteryThreshold {
            lowBatteryAlarm = LowBatteryAlarm(threshold: settings.lowBatteryThreshold)
        }
        if lowBatteryAlarm.update(chargePercent: battery.chargePercent, isCharging: battery.isCharging) {
            NotificationManager.shared.sendLowBattery(percent: battery.chargePercent)
        }
    }

    /// Read the A50 output volume from CoreAudio. Only devices that expose a
    /// settable software volume show the control — the A50's own outputs do not
    /// (volume is hardware / HID balance), so the card stays hidden for them.
    func refreshVolume() {
        guard let id = AudioDeviceVolume.a50OutputDevice(),
              let v = AudioDeviceVolume.volume(of: id) else {
            hasAudioDevice = false
            return
        }
        hasAudioDevice = true
        systemVolume = Double(v) * 100
    }

    func commitVolume() {
        guard let id = AudioDeviceVolume.a50OutputDevice() else { return }
        AudioDeviceVolume.setVolume(Float(systemVolume / 100), of: id)
    }

    /// Full one-shot load when the device appears. Cancels a previous load so
    /// a reconnect during a stalled load (each request can cost `timeout`)
    /// can't block the fresh one behind ~25 sequenced requests.
    func loadAll() {
        loadTask?.cancel()
        loadTask = Task { await performLoadAll() }
    }

    private func performLoadAll() async {
        func checkpoint() throws {
            if Task.isCancelled { throw CancellationError() }
        }
        do {
            battery = try await device.batteryStatus()
            headset = try await device.headsetStatus()
            activePreset = try await device.activeEQPreset()
            for preset in A50Limits.eqPresets {
                try checkpoint()
                presetNames[preset] = try await device.eqPresetName(preset)
                presetGains[preset] = try await device.eqPresetGain(preset)
            }
            // Preload band freq/width so the Frequencies section opens instantly.
            for preset in A50Limits.eqPresets {
                try checkpoint()
                await loadBands(preset)
            }
            try checkpoint()
            for slider in SliderType.allCases {
                sliders[slider] = try await device.sliderValue(slider)
            }
            balanceRaw = try await device.defaultBalance().raw
            alertVolume = try await device.alertVolume()
            micEQ = try await device.micEQ()
            noiseGate = try await device.noiseGateMode()
            autoShutoffTimer = try? await device.autoShutoffTimer()
            deviceInfo = try? await device.deviceInfo()
            baseFirmware = try? await device.baseFirmwareVersion()
            headsetFirmware = try? await device.headsetFirmwareVersion()
        } catch is CancellationError {
            // Superseded by a newer load; keep whatever state it collected.
        } catch {
            note(error)
        }
        refreshVolume()
    }

    // MARK: - Writes (optimistic)

    // Discrete controls write immediately.

    func setActivePreset(_ preset: Int) {
        activePreset = preset
        write { try await self.device.setActiveEQPreset(preset) }
    }

    func renamePreset(_ preset: Int, name: String) {
        let trimmed = String(name.prefix(20))
        presetNames[preset] = trimmed
        write { try await self.device.setEQPresetName(preset, name: trimmed) }
    }

    /// Load center-frequency/bandwidth for every band of a preset (once).
    func loadBands(_ preset: Int) async {
        guard presetBands[preset] == nil else { return }
        var bands: [EQPresetBand] = []
        do {
            for band in A50Limits.eqBands {
                bands.append(try await device.eqPresetBand(preset, band: band))
            }
            presetBands[preset] = bands
        } catch {
            note(error)
        }
    }

    // Continuous controls: `preview*` updates local state during a drag (no IO),
    // `commit*` writes the settled value to the device when the drag ends.

    func previewGain(preset: Int, band: Int, db: Int) {
        guard var current = presetGains[preset], current.gain.indices.contains(band) else { return }
        current.gain[band] = db
        presetGains[preset] = current
    }

    func commitGains(preset: Int) {
        guard let gains = presetGains[preset]?.gain else { return }
        write { try await self.device.setEQPresetGain(preset, gain: gains) }
    }

    func previewBand(preset: Int, index: Int, centerFreq: Int? = nil, bandwidth: Int? = nil) {
        guard var bands = presetBands[preset], bands.indices.contains(index) else { return }
        if let centerFreq { bands[index].centerFreq = centerFreq }
        if let bandwidth { bands[index].bandwidth = bandwidth }
        presetBands[preset] = bands
    }

    func commitBand(preset: Int, index: Int) {
        guard let bands = presetBands[preset], bands.indices.contains(index) else { return }
        let value = bands[index]
        write {
            try await self.device.setEQPresetBand(
                preset, band: index + 1, centerFreq: value.centerFreq, bandwidth: value.bandwidth)
        }
    }

    func previewSlider(_ slider: SliderType, percent: Int) {
        sliders[slider] = percent
    }

    func commitSlider(_ slider: SliderType) {
        guard let percent = sliders[slider] else { return }
        write { try await self.device.setSliderValue(slider, percent: percent) }
    }

    func commitBalance() {
        let raw = balanceRaw
        write { try await self.device.setDefaultBalance(raw) }
    }

    func commitAlertVolume() {
        let percent = alertVolume
        write { try await self.device.setAlertVolume(percent) }
    }

    func setMicEQ(_ preset: Int) {
        micEQ = preset
        write { try await self.device.setMicEQ(preset) }
    }

    func setNoiseGate(_ mode: NoiseGateMode) {
        noiseGate = mode
        write { try await self.device.setNoiseGateMode(mode) }
    }

    /// Persists the live values to the headset. `completion` reports whether the
    /// write succeeded so the UI can confirm it.
    func saveToDevice(completion: (@MainActor (Bool) -> Void)? = nil) {
        write({ try await self.device.save() }, completion: completion)
    }

    private func write(
        _ operation: @escaping @Sendable () async throws -> Void,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        Task {
            do {
                try await operation()
                lastError = nil
                completion?(true)
            } catch {
                note(error)
                if device.isConnected {
                    loadAll()
                }
                completion?(false)
            }
        }
    }

    /// Surfaces a message in the panel footer (used for failures that never
    /// reach the device, like a bad preset file).
    func report(_ message: String) {
        lastError = message
    }

    private func note(_ error: Error) {
        if let a50 = error as? A50Error {
            if case .deviceNotConnected = a50 {
                Task { await refreshDisconnectedStatus() }
            }
            lastError = a50.errorDescription
        } else {
            lastError = error.localizedDescription
        }
    }
}
