import AppKit
import AstroBarCore
import SwiftUI
import Testing
@testable import AstroBar

@MainActor
@Suite("UI render snapshots")
struct RenderTests {
    private func render(_ view: some View, to path: String, width: CGFloat = 340) {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("render failed for \(path)")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    @Test("render root panel")
    func rootPanel() {
        let monitor = A50Monitor()
        monitor.seedPreview()
        // The Gen 4 panel depends on these: Save and the preset menu are gated on them.
        #expect(monitor.family == .gen4)
        #expect(monitor.capabilities.contains(.saveToDevice))
        #expect(monitor.capabilities.contains(.equalizerPresets))
        render(MenuPanelView(monitor: monitor), to: "/tmp/panel_root.png")
    }

    @Test("render A50 X panel")
    func logitechPanel() {
        let monitor = A50Monitor()
        monitor.seedLogitechPreview()
        #expect(monitor.family == .logitech(productID: A50X.a50XProductID))
        render(MenuPanelView(monitor: monitor), to: "/tmp/panel_logitech.png")
    }

    @Test("render EQ editor")
    func eqEditor() {
        let monitor = A50Monitor()
        monitor.seedPreview()
        render(EQPresetEditor(monitor: monitor, preset: 1).padding(12), to: "/tmp/panel_eq.png")
    }

    @Test("render settings")
    func settings() {
        let monitor = A50Monitor()
        monitor.seedPreview()
        render(
            SettingsView(
                monitor: monitor,
                settings: AppSettings(),
                selection: SettingsSelection(),
                onSelectionChange: { _ in }),
            to: "/tmp/panel_settings.png",
            width: 720)
    }
}
