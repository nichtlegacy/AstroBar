import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Open panel for preset files.
///
/// The menu panel has to be dismissed before this runs: it sits at
/// `.popUpMenu` window level and would cover the dialog.
@MainActor
enum EQTemplateIO {
    /// Reads a preset file the user picks.
    enum ImportResult {
        case cancelled
        case presets([EQTemplate])
        case failure(String)
    }

    static func importPresets() -> ImportResult {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Equalizer Presets"
        panel.prompt = "Import"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        do {
            return .presets(try EQTemplateFile.decode(try Data(contentsOf: url)))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

/// Lets a view deep in the panel close the panel — needed before running a
/// modal file dialog.
private struct DismissMenuPanelKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var dismissMenuPanel: @MainActor () -> Void {
        get { self[DismissMenuPanelKey.self] }
        set { self[DismissMenuPanelKey.self] = newValue }
    }
}
