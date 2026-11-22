import AppKit
import Observation
import SwiftUI

/// What the indicator currently shows.
@MainActor
@Observable
final class VolumeHUDModel {
    var level = 0
    var maximum = 21
}

/// A small on-screen volume indicator, shown when the volume keys change the
/// headset's level. macOS draws its own only for outputs it can control, and
/// the A50 X is not one of them.
@MainActor
final class VolumeHUD {
    private let model = VolumeHUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private static let size = NSSize(width: 236, height: 52)
    private static let visibleFor: Duration = .milliseconds(1300)
    private static let fadeDuration = 0.25

    func show(level: Int, of maximum: Int) {
        model.level = level
        model.maximum = max(1, maximum)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled, let self, let panel = self.panel else { return }
            self.fadeOut(panel)
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    /// Kept synchronous on purpose: called from async code, the animation
    /// group would resolve to its `async` overload.
    private func fadeOut(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: VolumeHUDView(model: model))
        return panel
    }

    /// Lower centre of the screen that has keyboard focus.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - Self.size.width / 2,
            y: frame.minY + 96)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
    }
}

private struct VolumeHUDView: View {
    let model: VolumeHUDModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 26)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.18))
                    Capsule()
                        .fill(.primary)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 6)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Headset volume")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }

    private var fraction: Double {
        Double(model.level) / Double(model.maximum)
    }

    private var symbol: String {
        switch fraction {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
