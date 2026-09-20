import SwiftUI

/// Full view: complete lists, message previews and settings.
struct MainWindowView: View {
    @Bindable var state: AppState
    let controller: RefreshController

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()
            statusBar
        }
        .frame(minWidth: 680, minHeight: 440)
    }

    /// Finder-style status bar: the totals, plus when they were last checked.
    private var statusBar: some View {
        HStack(spacing: 12) {
            Label("\(state.visiblePullRequests.count)", systemImage: StatusBarTitleBuilder.pullRequestSymbol)
                .help("Reviews requested")
            Label("\(state.visibleNotifications.count)", systemImage: StatusBarTitleBuilder.mentionSymbol)
                .help("Unread mentions")

            Spacer()

            if state.loadState == .loading {
                ProgressView().controlSize(.small)
            }
            Text(state.statusMessage)
                .foregroundStyle(state.health == .failing ? .red : .secondary)

            Button {
                Task { await controller.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.accessoryBar)
            .disabled(state.loadState == .loading)
            .help("Refresh now")
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private func badge(for tab: MainWindowTab) -> Int {
        switch tab {
        case .pullRequests: state.visiblePullRequests.count
        case .mentions: state.visibleNotifications.count
        case .settings: 0
        }
    }

    // MARK: - Pull requests

    private var pullRequestList: some View {
        let items = state.visiblePullRequests
        return VStack(spacing: 0) {
            ListToolbar(
                settings: state.settings,
                keyPath: \.listGrouping,
                options: ListGrouping.forPullRequests
            ) {
                // Draft visibility belongs next to the list it changes, not
                // only buried in settings.
                if state.draftCount > 0 {
                    DraftToggleControl(settings: state.settings, draftCount: state.draftCount)
                }
            }
            Divider()

            GroupedList(
                items: items,
                grouping: state.settings.listGrouping,
                repository: \.repository
            ) { item in
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

    // MARK: - Mentions

    private var mentionList: some View {
        let items = state.visibleNotifications
        return VStack(spacing: 0) {
            ListToolbar(
                settings: state.settings,
                keyPath: \.notificationGrouping,
                options: ListGrouping.forNotifications
            ) {
                if !items.isEmpty {
                    Button("Mark all read") {
                        Task { await controller.markAllVisibleRead() }
                    }
                    .controlSize(.small)
                    .help("Marks these threads read on GitHub too")
                }
            }
            Divider()

            GroupedList(
                items: items,
                grouping: state.settings.notificationGrouping,
                repository: \.repository,
                type: \.subjectTypeLabel
            ) { item in
                NotificationRow(
                    item: item,
                    preview: state.previews[item.id],
                    isExpanded: state.expandedNotificationID == item.id,
                    toggle: { controller.togglePreview(for: item) },
                    markRead: { Task { await controller.markRead(item) } }
                )
                .padding(.vertical, 3)
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No unread mentions",
                        systemImage: StatusBarTitleBuilder.mentionSymbol,
                        description: Text(
                            state.notifications.isEmpty
                                ? "Nobody has mentioned you recently."
                                : "Unread notifications exist, but none match the reasons selected in settings."
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Building blocks

/// Bar above a list: the grouping switch plus whatever that list adds.
private struct ListToolbar<Trailing: View>: View {
    @Bindable var settings: Settings
    /// Which grouping preference this list drives; the two lists keep their
    /// own, since they offer different options.
    let keyPath: ReferenceWritableKeyPath<Settings, ListGrouping>
    let options: [ListGrouping]
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Picker("", selection: $settings[dynamicMember: keyPath]) {
                ForEach(options, id: \.self) { grouping in
                    Text(grouping.label).tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// A list that is either flat or split into per-repository sections.
///
/// Sections rather than tabs: a review queue can span a dozen repositories,
/// and tabs would hide most of them behind a scroll control while also
/// hiding the total. Sections keep everything countable on one screen.
private struct GroupedList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let grouping: ListGrouping
    let repository: (Item) -> String
    /// Nil for lists where grouping by type is meaningless.
    var type: ((Item) -> String)?
    @ViewBuilder var row: (Item) -> Row

    private var groupKey: ((Item) -> String)? {
        switch grouping {
        case .flat: nil
        case .byRepository: repository
        case .byType: type
        }
    }

    var body: some View {
        List {
            if let groupKey {
                ForEach(RepositoryGrouping.group(items, by: groupKey)) { group in
                    Section {
                        ForEach(group.items) { row($0) }
                    } header: {
                        HStack(spacing: 6) {
                            Text(group.repository)
                            Text(verbatim: "\(group.items.count)")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            } else {
                ForEach(items) { row($0) }
            }
        }
    }
}

/// Draft visibility. Also changes the menu bar count, which the label says.
private struct DraftToggleControl: View {
    @Bindable var settings: Settings
    let draftCount: Int

    var body: some View {
        Toggle(isOn: $settings.includeDrafts) {
            Text("Show \(draftCount) draft\(draftCount == 1 ? "" : "s")")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .help("Drafts are counted in the menu bar only while shown")
    }
}
