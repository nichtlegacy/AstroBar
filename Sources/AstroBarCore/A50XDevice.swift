import Foundation

/// High-level, typed access to an A50 X / A50 Gen 5 base station.
///
/// Mirrors `A50Device`: requests are serialized on a private queue so only one
/// read is ever waiting for its reply.
public actor A50XDevice {
    private let transport: A50XTransport
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "de.nichtlegacy.astrobar.hid.a50x.requests")
    private var started = false

    public init(transport: A50XTransport = A50XTransport(), timeout: TimeInterval = 1.5) {
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

    /// USB product id of the connected base station, if any.
    public nonisolated var productID: Int? { transport.productID }

    public nonisolated func setConnectionChangeHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        transport.onConnectionChange = handler
    }

    /// Receives every value frame, including ones the device sends on its own
    /// (for example when the volume wheel is turned).
    public nonisolated func setMessageHandler(_ handler: @escaping @Sendable (A50XMessage) -> Void) {
        transport.onMessage = handler
    }

    // MARK: - Core

    /// Sends a read request for an arbitrary command id and returns the
    /// payload of the reply. For diagnostics; it only ever sends a read.
    public func rawRead(command: UInt8) async throws -> [UInt8] {
        try await read(commandID: command)
    }

    private func read(_ command: A50XCommand) async throws -> [UInt8] {
        try await read(commandID: command.rawValue)
    }

    private func read(commandID: UInt8) async throws -> [UInt8] {
        let frame = A50XFrame.encode(command: commandID, handle: A50XFrame.readHandle)
        let transport = self.transport
        let timeout = self.timeout
        let queue = self.queue
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try transport.request(frame, timeout: timeout).payload)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func write(_ frame: [UInt8]) async throws {
        let transport = self.transport
        let queue = self.queue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try transport.send(frame)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Values

    /// Battery level, with `isCharging` set while the headset sits on the base
    /// below a full charge.
    public func battery() async throws -> (status: BatteryStatus, isDocked: Bool) {
        guard let value = A50XValue.battery(try await read(.battery)) else {
            throw A50Error.malformedResponse
        }
        let status = BatteryStatus(isCharging: value.isDocked && value.percent < 100, chargePercent: value.percent)
        return (status, value.isDocked)
    }

    /// Headset master volume, 0…21.
    public func volume() async throws -> Int {
        guard let level = A50XValue.volume(try await read(.volume)) else {
            throw A50Error.malformedResponse
        }
        return level
    }

    /// Set the headset master volume (0…21). This moves the same level the
    /// wheel on the headset controls.
    public func setVolume(_ level: Int) async throws {
        let clamped = max(A50X.volumeRange.lowerBound, min(A50X.volumeRange.upperBound, level))
        try await write(A50XFrame.encode(
            command: A50XCommand.volume.rawValue,
            handle: A50XFrame.volumeSetHandle,
            payload: [0xFF, UInt8(clamped)]))
    }

    // MARK: - Settings

    private func clamp(_ value: Int, to range: ClosedRange<Int>) -> UInt8 {
        UInt8(max(range.lowerBound, min(range.upperBound, value)))
    }

    /// Sidetone level, 0 (off) … 6.
    public func sidetone() async throws -> Int {
        guard let level = A50XValue.sidetone(try await read(.sidetone)) else {
            throw A50Error.malformedResponse
        }
        return level
    }

    public func setSidetone(_ level: Int) async throws {
        try await write(A50XFrame.encode(
            command: A50XCommand.sidetone.rawValue,
            handle: A50XFrame.settingSetHandle,
            payload: [0x01, 0xFF, clamp(level, to: A50X.sidetoneRange)]))
    }

    /// Brightness of the base station's light, 0…100.
    public func dockLight() async throws -> Int {
        guard let value = A50XValue.dockLight(try await read(.dockLight)) else {
            throw A50Error.malformedResponse
        }
        return value
    }

    public func setDockLight(_ percent: Int) async throws {
        try await write(A50XFrame.encode(
            command: A50XCommand.dockLight.rawValue,
            handle: A50XFrame.settingSetHandle,
            payload: [clamp(percent, to: A50X.dockLightRange)]))
    }

    /// Raw noise gate mode id; see `A50XNoiseGate` for the named ones.
    public func noiseGate() async throws -> UInt8 {
        guard let raw = A50XValue.noiseGate(try await read(.noiseGate)) else {
            throw A50Error.malformedResponse
        }
        return raw
    }

    public func setNoiseGate(_ mode: A50XNoiseGate) async throws {
        try await write(A50XFrame.encode(
            command: A50XCommand.noiseGate.rawValue,
            handle: A50XFrame.noiseGateSetHandle,
            payload: [mode.rawValue]))
    }

    /// Game/voice mix position, 0 (all voice) … 12 (all game).
    public func chatMix() async throws -> Int {
        guard let value = A50XValue.chatMix(try await read(.chatMix)) else {
            throw A50Error.malformedResponse
        }
        return value
    }
}
