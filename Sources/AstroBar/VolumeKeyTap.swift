import AppKit
import ApplicationServices

/// Intercepts the keyboard's volume keys so they can drive the headset's own
/// volume instead of the macOS mixer.
///
/// The A50 X exposes no volume control to CoreAudio, so with it selected as
/// the output the volume keys do nothing. Catching the keys needs an event tap,
/// and an event tap that can swallow events needs the Accessibility permission.
@MainActor
final class VolumeKeyTap {
    enum Key {
        case up
        case down
        case mute
    }

    /// Called for every volume key event. Return true to swallow the event
    /// (the system then never sees it), false to let it through untouched.
    /// `isDown` is false for the matching key-up, which should get the same
    /// answer as its key-down.
    var handler: (@MainActor (Key, _ isDown: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security.
    static func requestPermission() {
        // The literal is the value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Returns false when the tap could not be created, which means the
    /// Accessibility permission has not been granted yet.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedEventType)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: volumeKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = runLoopSource
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    // MARK: - Event handling

    /// NX_SYSDEFINED: the event type media keys arrive as.
    fileprivate static let systemDefinedEventType: UInt32 = 14
    /// Subtype of system-defined events that carry media keys.
    private static let mediaKeySubtype: Int16 = 8

    /// Decides what happens to one event. Returns true to swallow it.
    fileprivate func process(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type.rawValue == Self.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.mediaKeySubtype else { return false }

        // data1 packs the key code in the high word and the key state in
        // the second-lowest byte (0x0A down, 0x0B up).
        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let state = (data & 0xFF00) >> 8
        let key: Key
        switch keyCode {
        case 0: key = .up // NX_KEYTYPE_SOUND_UP
        case 1: key = .down // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute // NX_KEYTYPE_MUTE
        default: return false
        }
        return handler?(key, state == 0x0A) ?? false
    }
}

/// Carries the callback's arguments onto the main actor. The tap's source is
/// on the main run loop, so nothing here actually changes threads.
private struct TapEvent: @unchecked Sendable {
    let type: CGEventType
    let event: CGEvent
    let owner: UnsafeMutableRawPointer
}

/// C entry point of the event tap. Always runs on the main thread.
private func volumeKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let received = TapEvent(type: type, event: event, owner: userInfo)
    let swallow = MainActor.assumeIsolated {
        Unmanaged<VolumeKeyTap>.fromOpaque(received.owner).takeUnretainedValue()
            .process(type: received.type, event: received.event)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
