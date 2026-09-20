import SwiftUI

/// The sidebar column.
///
/// Hosted in its own `NSSplitViewItem` so AppKit treats it as a real sidebar.
/// That is what lines the toolbar's own split up with the divider below it — a
/// SwiftUI `NavigationSplitView` inside a plain hosting view leaves the two a
/// few points apart.
struct SidebarColumn: View {
    @Bindable var state: AppState

    var body: some View {
        List(selection: $state.sidebarSelection) {
            Section("Reviews Requested") {
                Label("All", systemImage: StatusBarTitleBuilder.pullRequestSymbol)
                    .badge(state.visiblePullRequests.count)
                    .tag(SidebarSelection.pullRequests(repository: nil))

                ForEach(state.pullRequestRepositories) { entry in
                    repositoryRow(entry)
                        .tag(SidebarSelection.pullRequests(repository: entry.repository))
                }
            }

            Section("My Pull Requests") {
                Label("All", systemImage: "person.crop.circle")
                    .badge(state.visibleAuthoredPullRequests.count)
                    .tag(SidebarSelection.myPullRequests(repository: nil))

                ForEach(state.authoredRepositories) { entry in
                    repositoryRow(entry)
                        .tag(SidebarSelection.myPullRequests(repository: entry.repository))
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
                Label("Dashboard", systemImage: "chart.bar")
                    .tag(SidebarSelection.dashboard)
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
            }
        }
        .listStyle(.sidebar)
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
}

/// The content column: whichever list the sidebar points at, with the status
/// bar along its bottom edge so it stops at the sidebar, as Finder's does.
struct ContentColumn: View {
    @Bindable var state: AppState
    let controller: RefreshController

    var body: some View {
        // The band's height is read from the safe area rather than measured
        // by the window controller: a compact toolbar is as tall as whatever
        // the current list puts in it, so a height pushed in from outside
        // described the view before last until the window was resized.
        GeometryReader { proxy in
            list
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Carry the content's own background up behind the toolbar.
                // Without it the title bar band is one uniform colour across
                // both columns and the divider only starts below it; Notes
                // and Finder run the content background to the top so the
                // divider is continuous.
                .background {
                    Color(nsColor: .textBackgroundColor).ignoresSafeArea()
                }
                .overlay(alignment: .top) {
                    titleBarBand(height: proxy.safeAreaInsets.top)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider()
                        statusBar
                    }
                }
        }
    }

    @ViewBuilder
    private var list: some View {
        switch state.sidebarSelection {
        case .pullRequests: pullRequestList
        case .myPullRequests: authoredList
        case .mentions: mentionList
        case .dashboard: DashboardView(state: state, controller: controller)
        case .settings: SettingsView(state: state, controller: controller)
        }
    }

    /// The strip the rows scroll behind. Clear while the list sits at its top
    /// — nothing is passing behind it — and a thin material once it scrolls,
    /// so rows do not collide with the title.
    private func titleBarBand(height: CGFloat) -> some View {
        Rectangle()
            .fill(state.isContentScrolled ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear))
            .frame(height: height)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: state.isContentScrolled)
    }

    // MARK: - Lists

    private var pullRequestList: some View {
        let items = state.selectedPullRequests
        return GroupedList(
            items: items,
            grouping: state.settings.listGrouping,
            repository: \.repository
        ) { item in
            pullRequestRow(item)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "No reviews requested",
                    systemImage: StatusBarTitleBuilder.pullRequestSymbol,
                    description: Text(
                        state.selectedDraftCount > 0 && !state.settings.includeDrafts
                            ? "Only drafts are waiting; switch them on above to see them."
                            : "Nothing is waiting for your review."
                    )
                )
            }
        }
    }

    /// The user's own open pull requests: what they are waiting on others for.
    private var authoredList: some View {
        let items = state.selectedAuthoredPullRequests
        return GroupedList(
            items: items,
            grouping: state.settings.listGrouping,
            repository: \.repository
        ) { item in
            pullRequestRow(item)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "No open pull requests",
                    systemImage: "person.crop.circle",
                    description: Text(
                        state.selectedDraftCount > 0 && !state.settings.includeDrafts
                            ? "Only your drafts are open; switch them on above to see them."
                            : "You have nothing open and waiting on review."
                    )
                )
            }
        }
    }

    private var mentionList: some View {
        let items = state.selectedNotifications
        return GroupedList(
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

    private func pullRequestRow(_ item: PullRequestItem) -> some View {
        PullRequestRow(
            item: item,
            inspect: { controller.inspect(item) },
            isInspected: state.inspectedPullRequestID == item.id
        )
        .padding(.vertical, 3)
    }

    // MARK: - Status bar

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
}

/// The list's name, as its own toolbar item.
///
/// AppKit's own title sits hard against the sidebar divider; Notes and Mail
/// inset theirs. Rendering it here is what allows the leading space.
struct ToolbarTitle: View {
    @Bindable var state: AppState

    var body: some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .padding(.leading, 12)
            .help(title)
    }

    private var title: String {
        let selection = state.sidebarSelection
        if let subtitle = selection.subtitle {
            return "\(selection.title) — \(subtitle)"
        }
        return selection.title
    }
}

/// Controls belonging to the list on screen, hosted in a toolbar item.
struct ToolbarControls: View {
    @Bindable var state: AppState
    let controller: RefreshController

    var body: some View {
        HStack(spacing: 10) {
            switch state.sidebarSelection {
            case .pullRequests, .myPullRequests:
                GroupingPicker(
                    settings: state.settings,
                    keyPath: \.listGrouping,
                    options: ListGrouping.forPullRequests
                )
                if state.selectedDraftCount > 0 {
                    DraftToggleControl(settings: state.settings, draftCount: state.selectedDraftCount)
                }
            case .mentions:
                GroupingPicker(
                    settings: state.settings,
                    keyPath: \.notificationGrouping,
                    options: ListGrouping.forNotifications
                )
                if !state.selectedNotifications.isEmpty {
                    Button("Mark all read") {
                        Task { await controller.markAllVisibleRead() }
                    }
                    .help("Marks these threads read on GitHub too")
                }
            case .dashboard, .settings:
                EmptyView()
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }
}

// MARK: - Building blocks

/// A list that is either flat or split into sections.
///
/// Sections rather than tabs: a review queue can span a dozen repositories,
/// and tabs would hide most of them behind a scroll control while also hiding
/// the total. Sections keep everything countable on one screen.
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

/// The grouping switch, as a toolbar control.
private struct GroupingPicker: View {
    @Bindable var settings: Settings
    /// Which grouping preference this list drives; the two lists keep their
    /// own, since they offer different options.
    let keyPath: ReferenceWritableKeyPath<Settings, ListGrouping>
    let options: [ListGrouping]

    var body: some View {
        Picker("", selection: $settings[dynamicMember: keyPath]) {
            ForEach(options, id: \.self) { grouping in
                Text(grouping.label).tag(grouping)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// Draft visibility.
///
/// A button rather than a Toggle: a toolbar drops a toggle's label, leaving a
/// bare switch that says nothing about what it switches. The button carries
/// its state in its own wording.
private struct DraftToggleControl: View {
    @Bindable var settings: Settings
    let draftCount: Int

    var body: some View {
        Button {
            settings.includeDrafts.toggle()
        } label: {
            Label(
                settings.includeDrafts
                    ? "Hide drafts"
                    : "Show \(draftCount) draft\(draftCount == 1 ? "" : "s")",
                systemImage: settings.includeDrafts ? "eye.slash" : "eye"
            )
            // Toolbars show icons only unless told otherwise, and "8 drafts
            // hidden" is the part worth reading.
            .labelStyle(.titleAndIcon)
        }
        .help("Drafts are counted in the menu bar only while shown")
    }
}

/// The detail column.
///
/// Follows the selection itself rather than being swapped out by the window
/// controller. Replacing a split view item's view controller tears down a
/// hosting view that AppKit still holds tooltip tracking for, and the tooltip
/// manager then reads freed memory the next time the pointer moves — a crash
/// in dynamicToolTipString, not in any of this code.
struct InspectorColumn: View {
    @Bindable var state: AppState
    let controller: RefreshController

    var body: some View {
        if let item = state.inspectedPullRequest {
            PullRequestDetailView(
                item: item,
                detail: state.pullRequestDetails[item.id],
                reload: { controller.reloadDetail(for: item.id) },
                close: { controller.closeInspector() }
            )
        } else {
            // Kept in the hierarchy while the pane is closing, so nothing is
            // deallocated mid-gesture.
            Color.clear
        }
    }
}
