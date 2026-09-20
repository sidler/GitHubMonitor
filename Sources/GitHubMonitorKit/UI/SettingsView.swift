import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState
    let controller: RefreshController

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AccountSettingsView(state: state, controller: controller)
                GeneralSettingsView(settings: state.settings, controller: controller)
            }
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: Settings
    let controller: RefreshController

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
                .onChange(of: settings.refreshInterval) {
                    controller.restartTimer()
                }
                Text("GitHub asks clients not to poll faster than its own suggested interval; the app never goes below that, even at 1 minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pull requests") {
                Toggle("Include drafts", isOn: $settings.includeDrafts)
                    .toggleStyle(.switch)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
            }
        }
        .formStyle(.grouped)
    }
}
