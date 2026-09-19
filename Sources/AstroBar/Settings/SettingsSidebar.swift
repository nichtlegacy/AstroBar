import AppKit
import SwiftUI

/// Settings sidebar: tab navigation over sidebar vibrancy, with the app icon,
/// name, and version pinned to the bottom.
struct SettingsSidebar: View {
    @Binding var selection: SettingsTab

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    var body: some View {
        ZStack {
            MaterialBackground(material: .sidebar, fallback: Color(nsColor: .controlBackgroundColor))

            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(SettingsTab.allCases) { tab in
                        HStack(spacing: 9) {
                            SettingsIconChip(tab: tab)
                            Text(tab.title)
                        }
                        .tag(tab)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectSoftIfAvailable()

                Divider()

                HStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AstroBar")
                            .font(.callout.weight(.semibold))
                        Text(versionText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
    }
}
