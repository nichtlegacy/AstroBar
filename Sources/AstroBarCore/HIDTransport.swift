import Foundation
import IOKit
import IOKit.hid

/// Raw HID transport to the Astro A50 base station control interface.
///
/// Runs its own `CFRunLoop` on a dedicated thread so device-matching and
/// input-report callbacks are delivered without blocking the caller. A
/// `request` blocks the calling thread on a semaphore that the input callback
/// signals — so callers must never call `request` from the transport's own
/// run-loop thread (they don't: the device actor drives it).
public final class HIDTransport: @unchecked Sendable {
    private let manager: IOHIDManager
    private let lock = NSLock()

    private var device: IOHIDDevice?
    private var inputBuffer: UnsafeMutablePointer<UInt8>
    private var pending: Pending?

    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var stopSource: CFRunLoopSource?

    /// Values the run-loop teardown callback needs (C function pointers can't
    /// capture, so they travel through the source's `info` pointer).
    private final class StopContext {
        let manager: IOHIDManager
        let runLoop: CFRunLoop
        init(manager: IOHIDManager, runLoop: CFRunLoop) {
            self.manager = manager
            self.runLoop = runLoop
        }
    }

    /// Called (off the main thread) whenever the device connects or disconnects.
    public var onConnectionChange: (@Sendable (Bool) -> Void)?

    private struct Pending {
        let semaphore: DispatchSemaphore
        var response: [UInt8]?
    }

    public init() {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.inputBuffer = .allocate(capacity: A50.reportLength)
        self.inputBuffer.initialize(repeating: 0, count: A50.reportLength)
    }

    deinit {
        inputBuffer.deinitialize(count: A50.reportLength)
        inputBuffer.deallocate()
    }

    public var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return device != nil
    }

    // MARK: - Lifecycle

    /// Start the background run loop and begin matching the base station.
    public func start() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: A50.vendorID,
            kIOHIDProductIDKey: A50.baseStationProductID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)

        let thread = Thread { [weak self] in
            guard let self else { return }
            let runLoop: CFRunLoop = CFRunLoopGetCurrent()
            IOHIDManagerScheduleWithRunLoop(self.manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))

            var context = CFRunLoopSourceContext()
            context.version = 0
            context.info = Unmanaged.passRetained(StopContext(manager: self.manager, runLoop: runLoop)).toOpaque()
            context.perform = { info in
                guard let info else { return }
                let box = Unmanaged<StopContext>.fromOpaque(info).takeRetainedValue()
                IOHIDManagerUnscheduleFromRunLoop(box.manager, box.runLoop, CFRunLoopMode.defaultMode.rawValue)
                IOHIDManagerClose(box.manager, IOOptionBits(kIOHIDOptionsTypeNone))
                CFRunLoopStop(box.runLoop)
            }
            let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
            CFRunLoopAddSource(runLoop, source, .defaultMode)

            lock.lock()
            self.runLoop = runLoop
            self.stopSource = source
            lock.unlock()

            CFRunLoopRun()
        }
        thread.name = "de.nichtlegacy.astrobar.hid"
        thread.stackSize = 512 * 1024
        self.thread = thread
        thread.start()
    }

    /// Stop matching, close the manager, and end the background thread.
    /// The teardown runs on the transport's own run-loop thread so it can't
    /// race the callbacks.
    public func stop() {
        lock.lock()
        let runLoop = self.runLoop
        let source = stopSource
        self.runLoop = nil
        self.stopSource = nil
        self.thread = nil
        lock.unlock()
        guard let runLoop, let source else { return }
        CFRunLoopSourceSignal(source)
        CFRunLoopWakeUp(runLoop)
    }

    // MARK: - Request / response

    /// Send a raw request and block until the matching response arrives.
    /// `bytes` is the report payload (report id 0 is implied, not included).
    public func request(_ bytes: [UInt8], timeout: TimeInterval) throws -> [UInt8] {
        lock.lock()
        guard let connectedDevice = device else {
            lock.unlock()
            throw A50Error.deviceNotConnected
        }
        let semaphore = DispatchSemaphore(value: 0)
        pending = Pending(semaphore: semaphore, response: nil)
        lock.unlock()

        let status = bytes.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(connectedDevice, kIOHIDReportTypeOutput, 0, buf.baseAddress!, buf.count)
        }
        guard status == kIOReturnSuccess else {
            lock.lock(); pending = nil; lock.unlock()
            throw A50Error.sendFailed(status)
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            lock.lock(); pending = nil; lock.unlock()
            recover(from: connectedDevice)
            throw A50Error.timeout
        }

        lock.lock()
        let response = pending?.response
        let disconnected = self.device == nil
        pending = nil
        lock.unlock()

        guard let response else {
            if disconnected {
                throw A50Error.deviceNotConnected
            }
            throw A50Error.timeout
        }
        return response
    }

    // MARK: - Callbacks

    /// After a timeout the firmware can leave a half-processed request behind
    /// and answer the *next* request with the stale reply (eh-fifty observed
    /// the same and resets the device). Closing and reopening the HID device
    /// flushes that state; requests are serialized by `A50Device`, so this
    /// never races another exchange.
    private func recover(from device: IOHIDDevice) {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        lock.lock()
        if let previous = self.device, previous != device {
            // Detach from the replaced device before forgetting it.
            IOHIDDeviceRegisterInputReportCallback(previous, inputBuffer, A50.reportLength, nil, nil)
        }
        self.device = device
        lock.unlock()
        IOHIDDeviceRegisterInputReportCallback(
            device, inputBuffer, A50.reportLength, Self.inputCallback,
            Unmanaged.passUnretained(self).toOpaque())
        onConnectionChange?(true)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        lock.lock()
        if self.device == device { self.device = nil }
        // Fail any in-flight request so the caller doesn't hang.
        if let p = pending { p.semaphore.signal(); pending = nil }
        lock.unlock()
        onConnectionChange?(false)
    }

    private func received(_ report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
        lock.lock()
        if pending != nil {
            pending?.response = bytes
            pending?.semaphore.signal()
        }
        lock.unlock()
    }

    // C trampolines

    private static let matchCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
    }

    private static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
    }

    private static let inputCallback: IOHIDReportCallback = { context, _, _, _, _, report, length in
        guard let context else { return }
        Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().received(report, length: length)
    }
}
