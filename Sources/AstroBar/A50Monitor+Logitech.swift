import AstroBarCore
import Foundation

/// The A50 X / A50 Gen 5 side of the monitor: which family is connected and
/// when the `LogitechSession` is created, polled and dropped. Kept apart so
/// `A50Monitor` stays focused on the Gen 4.
extension A50Monitor {
    /// The connected family. The X wins when both base stations are plugged in.
    /// Derived from observed state only, so views follow it: anything that is
    /// connected without a Logitech session is the Gen 4.
    var family: DeviceFamily? {
        if let logitech { return .logitech(productID: logitech.productID) }
        return status == .connected ? .gen4 : nil
    }

    /// Name of the connected model, for the panel header.
    var modelName: String { family?.modelName ?? DeviceFamily.gen4.modelName }

    var capabilities: DeviceCapabilities { family?.capabilities ?? [] }

    func startLogitech() {
        // The hops through `Task` can arrive out of order, so the flag the
        // callback carries is not trusted: the session follows `isConnected`.
        xDevice.setConnectionChangeHandler { [weak self] _ in
            Task { @MainActor in
                await self?.handleLogitechConnectionChange()
            }
        }
        xDevice.setMessageHandler { [weak self] message in
            Task { @MainActor in
                self?.logitech?.handle(message)
            }
        }
        Task { await xDevice.start() }
    }

    private func handleLogitechConnectionChange() async {
        syncLogitechSession()
        if logitech == nil, !device.isConnected {
            await refreshDisconnectedStatus()
        }
        updateVolumeKeys()
    }

    /// Makes `logitech` match what is plugged in. Idempotent, and the only
    /// place the session is created or dropped, so the connection callbacks
    /// and the poll always agree.
    func syncLogitechSession() {
        if xDevice.isConnected {
            let productID = xDevice.productID ?? A50X.a50XProductID
            if logitech?.productID != productID { beginLogitech(productID: productID) }
        } else if logitech != nil {
            logitech = nil
            deviceInfo = nil
            // Everything on screen came from the X. If a Gen 4 is plugged in as
            // well, it has to be read again.
            gen4LoadDeferred = true
            lastError = nil
            resetBatteryTracking()
            updateVolumeKeys()
        }
        if logitech == nil, gen4LoadDeferred {
            gen4LoadDeferred = false
            if device.isConnected {
                status = .connected
                loadAll()
            }
        }
    }

    private func beginLogitech(productID: Int) {
        let session = LogitechSession(device: xDevice, productID: productID)
        // An error from a session that has been dropped since belongs to a
        // device that is gone; it must not reach whatever is shown now.
        session.reportError = { [weak self, weak session] error in
            guard let self, let session, self.logitech === session else { return }
            self.note(error)
        }
        logitech = session
        // A Gen 4 load still under way would publish its values into the X's
        // panel. It runs again once the X is gone.
        loadTask?.cancel()
        deviceInfo = DeviceInfo(vendorID: A50X.vendorID, productID: productID)
        baseFirmware = nil
        headsetFirmware = nil
        autoShutoffTimer = nil
        resetBatteryTracking()
        status = .connected
        lastError = nil
        updateVolumeKeys()
        Task {
            await refreshLogitech(session)
            await session.loadSettings()
        }
    }

    func refreshLogitech(_ session: LogitechSession) async {
        do {
            let reading = try await session.battery()
            guard logitech === session else { return }
            battery = reading.status
            // These stations do not report whether the headset is powered on,
            // so it is treated as linked whenever the base answers.
            headset = HeadsetStatus(isLinked: true, isDocked: reading.isDocked)
            try await session.refreshVolumeAndMix()
            guard logitech === session else { return }
            if status != .connected { status = .connected }
            lastError = nil
        } catch {
            guard logitech === session else { return }
            note(error)
        }
        checkLowBattery()
        updateBatteryProjection()
    }

    /// Re-evaluates whether the volume-key tap should exist. The router keeps
    /// it only while the setting is on, an X is connected and macOS allows it.
    func updateVolumeKeys() {
        let target = capabilities.contains(.volumeKeys) ? logitech : nil
        volumeKeys.update(enabled: settings?.routeVolumeKeys ?? false, target: target)
    }

    #if DEBUG
    /// Populate with representative A50 X data for offline UI rendering.
    func seedLogitechPreview() {
        status = .connected
        battery = BatteryStatus(isCharging: false, chargePercent: 73)
        headset = HeadsetStatus(isLinked: true, isDocked: false)
        deviceInfo = DeviceInfo(vendorID: A50X.vendorID, productID: A50X.a50XProductID)
        let session = LogitechSession(device: xDevice, productID: A50X.a50XProductID)
        session.seedPreview()
        logitech = session
    }
    #endif
}
