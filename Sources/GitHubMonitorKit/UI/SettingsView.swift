import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Display", selection: $settings.statusBarStyle) {
                    ForEach(StatusBarStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("Refresh") {
                Picker("Every", selection: $settings.refreshInterval) {
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("15 minutes").tag(TimeInterval(900))
                    Text("30 minutes").tag(TimeInterval(1800))
                }
                Text("GitHub asks clients not to poll faster than its own suggested interval; the app never goes below that, even at 1 minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pull requests") {
                Toggle("Include drafts", isOn: $settings.includeDrafts)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }
}
