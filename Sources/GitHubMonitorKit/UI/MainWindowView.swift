import SwiftUI

/// Full view: complete lists, message previews and settings.
struct MainWindowView: View {
    @Bindable var state: AppState
    let controller: RefreshController

    var body: some View {
        NavigationSplitView {
            List(MainWindowTab.allCases, id: \.self, selection: $state.selectedTab) { tab in
                Label(tab.label, systemImage: tab.symbolName)
                    .badge(badge(for: tab))
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            Group {
                switch state.selectedTab {
                case .pullRequests: pullRequestList
                case .mentions: mentionList
                case .settings: SettingsView(state: state, controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 440)
    }

    private func badge(for tab: MainWindowTab) -> Int {
        switch tab {
        case .pullRequests: state.visiblePullRequests.count
        case .mentions: state.notifications.count
        case .settings: 0
        }
    }

    private var pullRequestList: some View {
        let items = state.visiblePullRequests
        return VStack(spacing: 0) {
            // Draft visibility belongs next to the list it changes, not only
            // buried in settings.
            if state.draftCount > 0 {
                DraftVisibilityBar(settings: state.settings, draftCount: state.draftCount)
                Divider()
            }

            List(items) { item in
                PullRequestRow(item: item)
                    .padding(.vertical, 3)
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No reviews requested",
                        systemImage: StatusBarTitleBuilder.pullRequestSymbol,
                        description: Text(
                            state.draftCount > 0 && !state.settings.includeDrafts
                                ? "Only drafts are waiting; switch them on above to see them."
                                : "Nothing is waiting for your review."
                        )
                    )
                }
            }
        }
    }

    private var mentionList: some View {
        List(state.notifications) { item in
            NotificationRow(item: item)
                .padding(.vertical, 2)
        }
        .overlay {
            if state.notifications.isEmpty {
                ContentUnavailableView(
                    "No unread mentions",
                    systemImage: StatusBarTitleBuilder.mentionSymbol,
                    description: Text("Nobody has mentioned you recently.")
                )
            }
        }
    }
}

/// Draft visibility, placed above the list it affects. Also changes the menu
/// bar count, which the caption spells out.
private struct DraftVisibilityBar: View {
    @Bindable var settings: Settings
    let draftCount: Int

    var body: some View {
        HStack(spacing: 8) {
            // A switch, matching how the same options are presented in settings.
            Toggle("Show drafts", isOn: $settings.includeDrafts)
                .toggleStyle(.switch)
                .controlSize(.small)
            Text("\(draftCount) draft\(draftCount == 1 ? "" : "s") in this list — counted in the menu bar only while shown")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
