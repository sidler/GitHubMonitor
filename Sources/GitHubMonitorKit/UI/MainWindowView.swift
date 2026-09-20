import SwiftUI

/// Full view: complete lists, message previews and settings.
struct MainWindowView: View {
    @Bindable var state: AppState
    let controller: RefreshController
    /// Lets the pane ask the window for more room when it opens.
    var ensureRoomForInspector: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
            } detail: {
                Group {
                    switch state.sidebarSelection {
                    case .pullRequests: pullRequestList
                    case .mentions: mentionList
                    case .settings: SettingsView(state: state, controller: controller)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .inspector(isPresented: inspectorShown) {
                    if let item = state.inspectedPullRequest {
                        PullRequestDetailView(
                            item: item,
                            detail: state.pullRequestDetails[item.id],
                            reload: { controller.reloadDetail(for: item.id) },
                            close: { controller.closeInspector() }
                        )
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                    }
                }
            }

            Divider()
            statusBar
        }
        .frame(minWidth: 820, minHeight: 440)
        .onChange(of: state.inspectedPullRequestID) { _, id in
            if id != nil { ensureRoomForInspector() }
        }
    }

    /// The pane follows the selection: it is open exactly while a pull
    /// request is being inspected.
    private var inspectorShown: Binding<Bool> {
        Binding(
            get: { state.inspectedPullRequest != nil },
            set: { shown in
                if !shown { controller.closeInspector() }
            }
        )
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

    /// Sections rather than a flat list, as in Finder's own sidebar: each
    /// heading carries an "All" row plus one row per repository, so a single
    /// click reaches a repository's queue.
    private var sidebar: some View {
        List(selection: $state.sidebarSelection) {
            Section("Pull Requests") {
                Label("All", systemImage: StatusBarTitleBuilder.pullRequestSymbol)
                    .badge(state.visiblePullRequests.count)
                    .tag(SidebarSelection.pullRequests(repository: nil))

                ForEach(state.pullRequestRepositories) { entry in
                    repositoryRow(entry)
                        .tag(SidebarSelection.pullRequests(repository: entry.repository))
                }
            }

            Section("Mentions") {
                Label("All", systemImage: StatusBarTitleBuilder.mentionSymbol)
                    .badge(state.visibleNotifications.count)
                    .tag(SidebarSelection.mentions(repository: nil))

                ForEach(state.notificationRepositories) { entry in
                    repositoryRow(entry)
                        .tag(SidebarSelection.mentions(repository: entry.repository))
                }
            }

            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
            }
        }
    }

    private func repositoryRow(_ entry: SidebarRepository) -> some View {
        Label {
            // The owner is the same for most rows; the repository name is
            // what distinguishes them, so it gets the room.
            Text(entry.repository.split(separator: "/").last.map(String.init) ?? entry.repository)
                .help(entry.repository)
        } icon: {
            Image(systemName: "book.closed")
        }
        .badge(entry.count)
    }

    // MARK: - Pull requests

    private var pullRequestList: some View {
        let items = state.selectedPullRequests
        return VStack(spacing: 0) {
            ListToolbar(
                selection: state.sidebarSelection,
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
                PullRequestRow(
                    item: item,
                    inspect: { controller.inspect(item) },
                    isInspected: state.inspectedPullRequestID == item.id
                )
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
        let items = state.selectedNotifications
        return VStack(spacing: 0) {
            ListToolbar(
                selection: state.sidebarSelection,
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
    let selection: SidebarSelection
    @Bindable var settings: Settings
    /// Which grouping preference this list drives; the two lists keep their
    /// own, since they offer different options.
    let keyPath: ReferenceWritableKeyPath<Settings, ListGrouping>
    let options: [ListGrouping]
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            // Says what is on screen, as Finder's toolbar names the folder.
            VStack(alignment: .leading, spacing: 0) {
                Text(selection.title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = selection.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .help(selection.title)

            Spacer(minLength: 12)

            Picker("", selection: $settings[dynamicMember: keyPath]) {
                ForEach(options, id: \.self) { grouping in
                    Text(grouping.label).tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

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
