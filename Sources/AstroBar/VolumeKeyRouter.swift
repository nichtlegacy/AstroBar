import ApplicationServices
import Observation

/// A headset whose volume the Mac's volume keys can drive.
@MainActor
protocol VolumeKeyTarget: AnyObject {
    /// Current level, in `volumeRange` steps.
    var volumeLevel: Int { get }
    var volumeRange: ClosedRange<Int> { get }
    /// False until `volumeLevel` was actually read from the device, so a
    /// key press never starts from a made-up level.
    var hasVolumeLevel: Bool { get }
    func setVolumeLevel(_ level: Int)
    /// Whether this headset is the Mac's current default output.
    func isDefaultOutput() -> Bool
}

/// Routes the volume keys to a `VolumeKeyTarget`, but only when the user asked
/// for it, there is a target and macOS has granted Accessibility access. The
/// event tap exists only while all three hold.
@MainActor
@Observable
final class VolumeKeyRouter {
    enum State: Equatable {
        /// Not routing: the setting is off or there is no headset to route to.
        case off
        /// Enabled, but Accessibility access has not been granted.
        case needsPermission
        case active
    }

    private(set) var state: State = .off

    @ObservationIgnored private let tap = VolumeKeyTap()
    @ObservationIgnored private let hud = VolumeHUD()
    @ObservationIgnored private weak var target: VolumeKeyTarget?
    /// Level to return to when the mute key is pressed a second time.
    @ObservationIgnored private var levelBeforeMute: Int?

    init() {
        tap.handler = { [weak self] key, isDown in
            self?.handle(key, isDown: isDown) ?? false
        }
    }

    /// Re-evaluates whether the tap should exist. Cheap, so it is called on
    /// every poll, on connect/disconnect and when the setting changes.
    func update(enabled: Bool, target: VolumeKeyTarget?) {
        if target !== self.target { levelBeforeMute = nil }
        self.target = target
        guard enabled, target != nil else {
            stop()
            return
        }
        guard VolumeKeyTap.hasPermission, tap.start() else {
            tap.stop()
            state = .needsPermission
            return
        }
        state = .active
    }

    /// Shows the system prompt that sends the user to Privacy & Security.
    func requestPermission() {
        VolumeKeyTap.requestPermission()
    }

    private func stop() {
        tap.stop()
        levelBeforeMute = nil
        state = .off
    }

    /// Returns true to swallow the key. Anything not meant for the headset
    /// passes through untouched, key-up included.
    private func handle(_ key: VolumeKeyTap.Key, isDown: Bool) -> Bool {
        guard let target, target.hasVolumeLevel, target.isDefaultOutput() else { return false }
        guard isDown else { return true }

        let current = target.volumeLevel
        switch key {
        case .up:
            levelBeforeMute = nil
            target.setVolumeLevel(current + 1)
        case .down:
            levelBeforeMute = nil
            target.setVolumeLevel(current - 1)
        case .mute:
            // The remembered level only holds while the headset is still at the
            // level the mute set; a wheel turn or slider drag in between ends it.
            if let previous = levelBeforeMute, current == target.volumeRange.lowerBound {
                levelBeforeMute = nil
                target.setVolumeLevel(previous)
            } else if current > target.volumeRange.lowerBound {
                levelBeforeMute = current
                target.setVolumeLevel(target.volumeRange.lowerBound)
            } else {
                levelBeforeMute = nil
            }
        }
        hud.show(level: target.volumeLevel, of: target.volumeRange.upperBound)
        return true
    }
}
