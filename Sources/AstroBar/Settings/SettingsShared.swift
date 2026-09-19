import AppKit
import SwiftUI

// Shared building blocks of the settings window, following the pattern of a
// sidebar + detail panes settings layout.

/// Colored icon badge for a settings tab.
struct SettingsIconChip: View {
    let tab: SettingsTab

    var body: some View {
        Image(systemName: tab.icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tab.iconColor))
            .accessibilityHidden(true)
    }
}

/// Two-line row label: title plus an optional explanatory subtitle.
struct SettingsRowLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Switch toggle with a two-line label.
struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabel(title: title, subtitle: subtitle)
        }
        .toggleStyle(.switch)
    }
}

/// Small inline status indicator.
struct SettingsStatusDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(verbatim: label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

extension View {
    /// Progressive blur at scroll edges on macOS 26, no-op earlier.
    @ViewBuilder
    func scrollEdgeEffectSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }

    /// The grouped, transparent-background form look shared by all panes.
    func settingsFormStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}
