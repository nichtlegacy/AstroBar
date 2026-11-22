import AstroBarCore
import Foundation
import Observation

/// Everything the app tracks for a connected A50 X / A50 Gen 5: the values the
/// device reports, the reads that keep them current and the writes that change
/// them. `A50Monitor` creates one while such a base station is connected and
/// drops it when it goes away, so a session never outlives its device.
@MainActor
@Observable
final class LogitechSession: VolumeKeyTarget {
    /// USB product id of the base station this session talks to.
    let productID: Int

    /// Headset master volume, 0…21 (the wheel's steps).
    var headsetVolume: Double = 0
    /// Game/voice mix position, 0 (all voice) … 12 (all game).
    private(set) var chatMix: Int?
    /// Sidetone level 0…6, nil until the device has reported it.
    var sidetone: Double?
    /// Base station light brightness 0…100, nil until reported.
    var dockLight: Double?
    /// Raw noise gate mode id, nil until reported.
    private(set) var noiseGateRaw: UInt8?

    private let device: A50XDevice
    /// Where failed writes are reported; set by the monitor.
    @ObservationIgnored var reportError: @MainActor (Error) -> Void = { _ in }
    /// True once `headsetVolume` holds a level read from the device.
    @ObservationIgnored private var volumeKnown = false
    @ObservationIgnored private var isDraggingVolume = false
    /// When each value was last written from here. A read or push that was in
    /// flight at that moment still carries the old value and must not win.
    @ObservationIgnored private var localWrites: [A50XCommand: ContinuousClock.Instant] = [:]

    private static let settleWindow: Duration = .seconds(1)

    init(device: A50XDevice, productID: Int) {
        self.device = device
        self.productID = productID
    }

    #if DEBUG
    /// Representative values for offline rendering.
    func seedPreview() {
        headsetVolume = 12
        volumeKnown = true
        chatMix = 6
        sidetone = 2
        dockLight = 60
        noiseGateRaw = A50XNoiseGate.night.rawValue
    }
    #endif

    // MARK: - Reads

    /// The battery reading, polled by the monitor.
    func battery() async throws -> (status: BatteryStatus, isDocked: Bool) {
        try await device.battery()
    }

    /// Polls volume and mix. Both also arrive as pushes, so this is a safety
    /// net. A separate step from `battery()`, so a failed volume read does not
    /// cost the battery reading that came before it.
    func refreshVolumeAndMix() async throws {
        let started = ContinuousClock.now
        let level = try await device.volume()
        if !isSettling(.volume, since: started) { applyVolume(level) }
        chatMix = try? await device.chatMix()
    }

    /// Settings that only change when someone changes them: read once on
    /// connect, then kept current by the frames the device pushes.
    func loadSettings() async {
        let started = ContinuousClock.now
        let level = try? await device.sidetone()
        if !isSettling(.sidetone, since: started) { sidetone = level.map { Double($0) } }
        let light = try? await device.dockLight()
        if !isSettling(.dockLight, since: started) { dockLight = light.map { Double($0) } }
        let gate = try? await device.noiseGate()
        if !isSettling(.noiseGate, since: started) { noiseGateRaw = gate }
    }

    /// Applies a frame the device pushed (or answered) on its own.
    func handle(_ message: A50XMessage) {
        switch message.command {
        case A50XCommand.sidetone.rawValue:
            if !isSettling(.sidetone), let level = A50XValue.sidetone(message.payload) { sidetone = Double(level) }
        case A50XCommand.dockLight.rawValue:
            if !isSettling(.dockLight), let value = A50XValue.dockLight(message.payload) { dockLight = Double(value) }
        case A50XCommand.noiseGate.rawValue:
            if !isSettling(.noiseGate), let raw = A50XValue.noiseGate(message.payload) { noiseGateRaw = raw }
        case A50XCommand.volume.rawValue:
            if !isSettling(.volume), let level = A50XValue.volume(message.payload) { applyVolume(level) }
        case A50XCommand.chatMix.rawValue:
            if let value = A50XValue.chatMix(message.payload) { chatMix = value }
        default:
            break
        }
    }

    private func applyVolume(_ level: Int) {
        headsetVolume = Double(level)
        volumeKnown = true
    }

    /// True while a local change to `command` is still settling. A value that
    /// was read before `since` predates the latest local write.
    private func isSettling(_ command: A50XCommand, since started: ContinuousClock.Instant? = nil) -> Bool {
        if command == .volume, isDraggingVolume { return true }
        guard let written = localWrites[command] else { return false }
        if let started, written > started { return true }
        return ContinuousClock.now - written < Self.settleWindow
    }

    // MARK: - Writes

    /// Called by the volume slider when a drag starts and ends.
    func setVolumeDragging(_ dragging: Bool) {
        isDraggingVolume = dragging
    }

    func commitHeadsetVolume() {
        let level = Int(headsetVolume.rounded())
        write(.volume, { [device] in try await device.setVolume(level) },
              read: { [device] in try await device.volume() },
              apply: { [self] in
                  // Unread after a failed write, the level on screen is a guess:
                  // the volume keys stay with macOS until a read confirms it.
                  if let level = $0 { applyVolume(level) } else { volumeKnown = false }
              })
    }

    func commitSidetone() {
        guard let current = sidetone else { return }
        let level = Int(current.rounded())
        write(.sidetone, { [device] in try await device.setSidetone(level) },
              read: { [device] in try await device.sidetone() },
              apply: { [self] in sidetone = $0.map { Double($0) } })
    }

    func commitDockLight() {
        guard let current = dockLight else { return }
        let percent = Int(current.rounded())
        write(.dockLight, { [device] in try await device.setDockLight(percent) },
              read: { [device] in try await device.dockLight() },
              apply: { [self] in dockLight = $0.map { Double($0) } })
    }

    func setNoiseGate(_ mode: A50XNoiseGate) {
        noiseGateRaw = mode.rawValue
        write(.noiseGate, { [device] in try await device.setNoiseGate(mode) },
              read: { [device] in try await device.noiseGate() },
              apply: { [self] in noiseGateRaw = $0 })
    }

    /// Sends one write. When it fails the optimistic value on screen was never
    /// applied, so the device is asked what it actually holds; if that fails
    /// too, `apply` gets nil and the setting counts as unknown again. A newer
    /// write to the same value supersedes all of this.
    private func write<Value: Sendable>(
        _ command: A50XCommand,
        _ operation: @escaping @Sendable () async throws -> Void,
        read: @escaping @Sendable () async throws -> Value,
        apply: @escaping @MainActor (Value?) -> Void
    ) {
        let started = ContinuousClock.now
        localWrites[command] = started
        Task {
            do {
                try await operation()
                if localWrites[command] == started { localWrites[command] = .now }
            } catch {
                reportError(error)
                guard localWrites[command] == started else { return }
                let actual = try? await read()
                guard localWrites[command] == started else { return }
                localWrites[command] = nil
                apply(actual)
            }
        }
    }

    // MARK: - VolumeKeyTarget

    var volumeLevel: Int { Int(headsetVolume.rounded()) }
    var volumeRange: ClosedRange<Int> { A50X.volumeRange }
    var hasVolumeLevel: Bool { volumeKnown }

    func setVolumeLevel(_ level: Int) {
        let clamped = max(volumeRange.lowerBound, min(volumeRange.upperBound, level))
        guard clamped != volumeLevel else { return }
        headsetVolume = Double(clamped)
        commitHeadsetVolume()
    }

    func isDefaultOutput() -> Bool {
        AudioDeviceVolume.defaultOutputIsLogitechA50()
    }
}
