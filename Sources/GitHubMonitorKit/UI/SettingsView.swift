import Combine
import SwiftUI

/// Settings in tabs rather than one long form: account, filters and general
/// preferences together run to several screens, and burying "launch at login"
/// under two scrolls is a good way to make it undiscoverable.
struct SettingsView: View {
    @Bindable var state: AppState
    let controller: RefreshController

    var body: some View {
        TabView(selection: $state.selectedSettingsTab) {
            AccountSettingsView(state: state, controller: controller)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(SettingsTab.account)

            ListsSettingsView(state: state, controller: controller)
                .tabItem { Label("Lists", systemImage: "list.bullet.rectangle") }
                .tag(SettingsTab.lists)

            Form {
                RepositoryFilterView(state: state, controller: controller)
                FilterSettingsView(settings: state.settings)
            }
            .formStyle(.grouped)
            .tabItem { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
            .tag(SettingsTab.filters)

            GeneralSettingsView(state: state, settings: state.settings, controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
        }
        .padding(.top, 8)
    }
}

/// Filters that are not about repositories: drafts and notification reasons.
/// They live here rather than under General because that is what they are.
private struct FilterSettingsView: View {
    @Bindable var settings: Settings

    var body: some View {
        Group {
            Section("Pull requests") {
                Toggle("Include drafts", isOn: $settings.includeDrafts)
                    .toggleStyle(.switch)
                // Only the pull request lists have anything to hide here, and
                // the repository filter above applies to all three lists --
                // saying so is what keeps this section from reading like the
                // only filter there is.
                Text("Drafts count in the menu bar only while they are shown. Issues have no draft state, so this leaves them alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mentions") {
                Text("Which notification reasons count towards the badge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(NotificationReason.selectable, id: \.self) { reason in
                    Toggle(reason.label, isOn: reasonBinding(reason))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if settings.notificationReasons.isEmpty {
                    Label(
                        "With nothing selected the mention count stays at zero.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private func reasonBinding(_ reason: NotificationReason) -> Binding<Bool> {
        Binding(
            get: { settings.notificationReasons.contains(reason) },
            set: { isOn in
                var reasons = settings.notificationReasons
                if isOn {
                    reasons.insert(reason)
                } else {
                    reasons.remove(reason)
                }
                settings.notificationReasons = reasons
            }
        )
    }
}

@MainActor
private final class LoginItemModel: ObservableObject {
    @Published var message: String?

    /// Mirrors the system's own view rather than the stored preference, so a
    /// registration the system refused does not show as enabled.
    func syncFromSystem(into settings: Settings) {
        let actual = LaunchAtLogin.isEnabled
        if settings.launchAtLogin != actual {
            settings.launchAtLogin = actual
        }
        message = LaunchAtLogin.statusMessage(after: nil)
    }

    func apply(_ enabled: Bool, to settings: Settings) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            settings.launchAtLogin = enabled
            message = LaunchAtLogin.statusMessage(after: nil)
        } catch {
            // Put the switch back where the system actually is.
            settings.launchAtLogin = LaunchAtLogin.isEnabled
            message = LaunchAtLogin.statusMessage(after: error)
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var state: AppState
    /// The same object as `state.settings`, bound separately because the
    /// controls here write straight into it.
    @Bindable var settings: Settings
    let controller: RefreshController

    @StateObject private var loginItem = LoginItemModel()

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Display", selection: $settings.statusBarStyle) {
                    ForEach(StatusBarStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.inline)

                Text("The counts are whichever lists are switched on for the menu bar in the Lists tab. A single total adds them up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("Startup") {
                Toggle("Launch at login", isOn: loginItemBinding)
                    .toggleStyle(.switch)

                if let message = loginItem.message {
                    Label(message, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("The login item points at the app's current location, so moving the app afterwards breaks it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { loginItem.syncFromSystem(into: settings) }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { loginItem.apply($0, to: settings) }
        )
    }
}
