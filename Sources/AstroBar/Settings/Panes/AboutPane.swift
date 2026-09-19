import AppKit
import SwiftUI

struct AboutPane: View {
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 20) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 92, height: 92)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("AstroBar")
                            .font(.title.bold())
                        Text(versionText)
                            .foregroundStyle(.secondary)
                        Text("A native macOS menu bar companion for the Astro A50 (Gen 4) wireless headset.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            Section {
                Link(destination: URL(string: "https://github.com/nichtlegacy/AstroBar")!) {
                    Label("GitHub — nichtlegacy/AstroBar", systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://github.com/nichtlegacy/AstroBar/blob/main/LICENSE")!) {
                    Label("MIT License", systemImage: "doc.text")
                }
                Link(destination: URL(string: "https://github.com/tdryer/eh-fifty")!) {
                    Label("Protocol research — tdryer/eh-fifty", systemImage: "waveform.path.ecg")
                }
                Link(destination: URL(string: "https://github.com/XxUnkn0wnxX/TheZEFERENCE")!) {
                    Label("Bundled EQ presets — The ZEFERENCE by ZaliaS", systemImage: "slider.horizontal.3")
                }
            } header: {
                Text("Links")
            }

            Section {
                UpdatesSection()
            } header: {
                Text("Updates")
            } footer: {
                Text("Updates are verified by signature. The download is ad-hoc signed and not notarized, so macOS asks for confirmation the first time.")
            }

            Section {
                EmptyView()
            } footer: {
                Text(verbatim: "© 2026 nichtlegacy")
            }
        }
        .settingsFormStyle()
    }
}

/// Sparkle's controls: the two automatic behaviours, when it last looked, and a
/// manual check.
@MainActor
private struct UpdatesSection: View {
    @ObservedObject private var updater = UpdaterManager.shared

    private var lastCheckedText: String {
        guard let date = updater.lastUpdateCheckDate else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        SettingsToggle(
            "Check for updates automatically",
            subtitle: "Look for new releases in the background and ask before installing.",
            isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }))

        SettingsToggle(
            "Download updates in the background",
            subtitle: "Fetch releases ahead of time so they are ready to install.",
            isOn: Binding(
                get: { updater.automaticallyDownloadsUpdates },
                set: { updater.automaticallyDownloadsUpdates = $0 }))
            .disabled(!updater.automaticallyChecksForUpdates)

        LabeledContent("Last checked", value: lastCheckedText)

        HStack {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
            Spacer()
        }
    }
}
