import SwiftUI

/// Full view: complete lists, message previews and settings.
struct MainWindowView: View {
    @Bindable var state: AppState

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
                case .settings: SettingsView(settings: state.settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 440)
    }

    private func badge(for tab: MainWindowTab) -> Int {
        switch tab {
        case .pullRequests: state.pullRequests.count
        case .mentions: state.notifications.count
        case .settings: 0
        }
    }

    private var pullRequestList: some View {
        List(state.pullRequests) { item in
            PullRequestRow(item: item)
                .padding(.vertical, 2)
        }
        .overlay {
            if state.pullRequests.isEmpty {
                ContentUnavailableView(
                    "No reviews requested",
                    systemImage: StatusBarTitleBuilder.pullRequestSymbol,
                    description: Text("Nothing is waiting for your review.")
                )
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
