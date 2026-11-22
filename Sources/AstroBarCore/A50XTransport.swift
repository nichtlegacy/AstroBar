import Foundation
import IOKit
import IOKit.hid

/// Raw HID transport to an A50 X / A50 Gen 5 base station.
///
/// Same shape as `HIDTransport`, with one difference in the protocol: these
/// base stations also push frames on their own (turning the volume wheel, a
/// battery change), so a reply is matched to its request by command id, and
/// every decoded frame is also handed to `onMessage`.
public final class A50XTransport: @unchecked Sendable {
    private let manager: IOHIDManager
    private let lock = NSLock()

    private var device: IOHIDDevice?
    private var connectedProductID: Int?
    private var inputBuffer: UnsafeMutablePointer<UInt8>
    private var pending: Pending?

    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var stopSource: CFRunLoopSource?

    private final class StopContext {
        let manager: IOHIDManager
        let runLoop: CFRunLoop
        init(manager: IOHIDManager, runLoop: CFRunLoop) {
            self.manager = manager
            self.runLoop = runLoop
        }
    }

    /// Called (off the main thread) whenever the device connects or disconnects.
    /// Like `onMessage`, set it before `start()`: it is read without a lock.
    public var onConnectionChange: (@Sendable (Bool) -> Void)?

    /// Called (off the main thread) for every frame that carries a value,
    /// replies and unsolicited pushes alike.
    public var onMessage: (@Sendable (A50XMessage) -> Void)?

    private struct Pending {
        let command: UInt8
        let semaphore: DispatchSemaphore
        var response: A50XMessage?
    }

    public init() {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.inputBuffer = .allocate(capacity: A50X.reportLength)
        self.inputBuffer.initialize(repeating: 0, count: A50X.reportLength)
    }

    deinit {
        inputBuffer.deinitialize(count: A50X.reportLength)
        inputBuffer.deallocate()
    }

    public var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return device != nil
    }

    /// USB product id of the connected base station, if any.
    public var productID: Int? {
        lock.lock(); defer { lock.unlock() }
        return connectedProductID
    }

    // MARK: - Lifecycle

    public func start() {
        let matching: [[String: Any]] = A50X.productIDs.map { product in
            [
                kIOHIDVendorIDKey: A50X.vendorID,
                kIOHIDProductIDKey: product,
                kIOHIDDeviceUsagePageKey: A50X.vendorUsagePage,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

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
        thread.name = "de.nichtlegacy.astrobar.hid.a50x"
        thread.stackSize = 512 * 1024
        self.thread = thread
        thread.start()
    }

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

    // MARK: - Sending

    /// Send a frame without waiting for anything. Used for writes: the device
    /// only acknowledges them with an empty frame.
    public func send(_ frame: [UInt8]) throws {
        lock.lock()
        let connectedDevice = device
        lock.unlock()
        guard let connectedDevice else { throw A50Error.deviceNotConnected }
        try write(frame, to: connectedDevice)
    }

    /// Send a read request and block until a frame with the same command id
    /// and a value arrives. Must not be called from the transport's own thread.
    public func request(_ frame: [UInt8], timeout: TimeInterval) throws -> A50XMessage {
        guard frame.count > 4 else { throw A50Error.invalidArgument("frame too short") }

        lock.lock()
        guard let connectedDevice = device else {
            lock.unlock()
            throw A50Error.deviceNotConnected
        }
        let semaphore = DispatchSemaphore(value: 0)
        pending = Pending(command: frame[4], semaphore: semaphore, response: nil)
        lock.unlock()

        do {
            try write(frame, to: connectedDevice)
        } catch {
            lock.lock(); pending = nil; lock.unlock()
            throw error
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            lock.lock(); pending = nil; lock.unlock()
            throw A50Error.timeout
        }

        lock.lock()
        let response = pending?.response
        let disconnected = self.device == nil
        pending = nil
        lock.unlock()

        guard let response else {
            throw disconnected ? A50Error.deviceNotConnected : A50Error.timeout
        }
        return response
    }

    private func write(_ frame: [UInt8], to device: IOHIDDevice) throws {
        guard let reportID = frame.first else { throw A50Error.invalidArgument("empty frame") }
        let status = frame.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), buf.baseAddress!, buf.count)
        }
        guard status == kIOReturnSuccess else { throw A50Error.sendFailed(status) }
    }

    // MARK: - Callbacks

    private func deviceMatched(_ device: IOHIDDevice) {
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
        lock.lock()
        if let previous = self.device, previous != device {
            IOHIDDeviceRegisterInputReportCallback(previous, inputBuffer, A50X.reportLength, nil, nil)
        }
        self.device = device
        self.connectedProductID = product
        lock.unlock()
        IOHIDDeviceRegisterInputReportCallback(
            device, inputBuffer, A50X.reportLength, Self.inputCallback,
            Unmanaged.passUnretained(self).toOpaque())
        onConnectionChange?(true)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        lock.lock()
        guard self.device == device else {
            lock.unlock()
            return
        }
        self.device = nil
        self.connectedProductID = nil
        if let waiting = pending { waiting.semaphore.signal() }
        lock.unlock()
        onConnectionChange?(false)
    }

    private func received(_ report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
        // Frames without a payload are bare acknowledgements of a write.
        guard let message = A50XFrame.decode(bytes), !message.payload.isEmpty else { return }

        lock.lock()
        if let waiting = pending, waiting.response == nil, waiting.command == message.command {
            pending?.response = message
            waiting.semaphore.signal()
        }
        lock.unlock()

        onMessage?(message)
    }

    // C trampolines

    private static let matchCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<A50XTransport>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
    }

    private static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<A50XTransport>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
    }

    private static let inputCallback: IOHIDReportCallback = { context, _, _, _, _, report, length in
        guard let context else { return }
        Unmanaged<A50XTransport>.fromOpaque(context).takeUnretainedValue().received(report, length: length)
    }
}
