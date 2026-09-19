import AstroBarCore
import SwiftUI

struct FooterView: View {
    let monitor: A50Monitor
    var onOpenSettings: () -> Void = {}

    /// Transient state of the last "Save" press, shown on the button itself.
    /// Writing to the headset takes a second or two, so the press is
    /// acknowledged before the result is known.
    private enum SaveState: Equatable {
        case saving
        case saved
        case failed

        var title: String {
            switch self {
            case .saving: "Saving…"
            case .saved: "Saved"
            case .failed: "Error"
            }
        }

        var symbol: String {
            switch self {
            case .saving: "internaldrive"
            case .saved: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }

        /// Nil keeps the button's ordinary accent colour.
        var tint: Color? {
            switch self {
            case .saving: nil
            case .saved: .green
            case .failed: .red
            }
        }
    }

    @State private var saveState: SaveState?
    @State private var saveGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if let error = monitor.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button {
                    save()
                } label: {
                    Label(saveState?.title ?? "Save", systemImage: saveState?.symbol ?? "internaldrive")
                        .contentTransition(.identity)
                }
                .tint(saveState?.tint)
                .disabled(saveState == .saving)
                .help("Persist current values to the headset so they survive a power cycle.")
                .accessibilityLabel("Save to headset")
                .accessibilityValue(saveState?.title ?? "")

                Spacer()

                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .help("Open Settings")

                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .accessibilityLabel("Quit AstroBar")
                .help("Quit AstroBar")
                .keyboardShortcut("q")
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: saveState)
        }
    }

    /// Turns the button into its own result readout, then back. A later press
    /// supersedes the pending reset so the label doesn't revert early.
    private func save() {
        saveGeneration &+= 1
        let generation = saveGeneration
        saveState = .saving
        monitor.saveToDevice { succeeded in
            guard saveGeneration == generation else { return }
            saveState = succeeded ? .saved : .failed
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                if saveGeneration == generation { saveState = nil }
            }
        }
    }
}
