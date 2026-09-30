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
                // No switch here any more: drafts are a property of a list,
                // set where the list is on screen. Saying where keeps this
                // from reading as though the setting had been dropped.
                Text("Drafts are shown or hidden per list, from the eye in the window's toolbar or beside the list in the popover. They count in the menu bar only while shown.")
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

            Section("Waiting reviews") {
                Picker("Mark after", selection: $settings.agingDays) {
                    ForEach([1, 2, 3, 5, 7], id: \.self) { days in
                        Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                    }
                }
                Picker("Call it overdue after", selection: $settings.overdueDays) {
                    ForEach([3, 5, 7, 10, 14], id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }

                Text("The date in a pull request row turns orange, then red, once your review has been waiting that long. Only a review asked of you by name carries a clock \u{2014} a request made of a team names the team, not you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sidebar") {
                Toggle("Hide the repository row when a list has only one", isOn: $settings.hidesSingleRepository)
                    .toggleStyle(.switch)

                Text("A section covering a single repository names it in a row of its own, below a count that already covers everything. Switching this on gives that line back to the lists.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diff") {
                Stepper(value: $settings.diffFontSize,
                        in: Settings.smallestDiffFontSize...Settings.largestDiffFontSize,
                        step: 1) {
                    // A LabeledContent here would huddle against the label
                    // instead of sitting under the values of the rows above:
                    // a Stepper's label is given only the width it asks for.
                    HStack {
                        Text("Text size")
                        Spacer()
                        Text(verbatim: "\(Int(settings.diffFontSize)) pt").monospacedDigit()
                    }
                }

                // Shown at the size being chosen, because "13 pt" answers a
                // different question than the one being asked.
                Text(verbatim: "@@ -1,4 +1,4 @@  func send(_ message: Message) throws {")
                    .font(.system(size: settings.diffFontSize).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("The patch only. File names and the tree beside them keep their size, and \u{2318}+ and \u{2318}\u{2212} change this while a diff is open.")
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

                Text(RefreshCost.sentence(
                    lastRefreshCost: state.lastRefreshCost,
                    interval: settings.refreshInterval
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("GitHub's hourly budget") {
                budgetRow("Queries (lists, charts)", budget: state.budgets.graphQL)
                budgetRow("Notifications", budget: state.budgets.rest)

                Text("Two separate allowances, read from GitHub's own answers. Refreshing stops on its own below \(RateBudget.pauseFloor) query points and picks up again when they are restored.")
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

    @ViewBuilder
    private func budgetRow(_ name: String, budget: RateBudget?) -> some View {
        LabeledContent(name) {
            if let budget, !budget.isStale() {
                HStack(spacing: 8) {
                    Text(verbatim: "\(budget.remaining) of \(budget.limit)")
                        .monospacedDigit()
                        .foregroundStyle(budget.isLow ? Color.orange : Color(nsColor: .labelColor))
                    if let reset = budget.resetAt {
                        Text("resets \(RelativeTime.clock(reset))")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Either nothing has been fetched yet, or the hour has turned
                // and what we knew is worth nothing.
                Text("not measured since the last reset").foregroundStyle(.secondary)
            }
        }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { loginItem.apply($0, to: settings) }
        )
    }
}
