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
                    BottomBar { statusBar }
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
            repository: \.repository,
            selection: $state.inspectedPullRequestID
        ) { item in
            pullRequestRow(item)
        }
        // Escape puts the detail pane away, as it does everywhere else.
        .onExitCommand { controller.closeInspector() }
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
            repository: \.repository,
            selection: $state.inspectedPullRequestID
        ) { item in
            pullRequestRow(item)
        }
        .onExitCommand { controller.closeInspector() }
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
            type: \.subjectTypeLabel,
            selection: $state.expandedNotificationID
        ) { item in
            NotificationRow(
                item: item,
                preview: state.previews[item.id],
                isExpanded: state.expandedNotificationID == item.id,
                // The message goes into the detail pane here; expanding the
                // row in place would push the rest of the list down.
                inlinePreview: false,
                toggle: { controller.inspect(item) },
                markRead: { Task { await controller.markRead(item) } }
            )
            .padding(.vertical, 3)
        }
        .onExitCommand { controller.closeInspector() }
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
            sort: state.settings.pullRequestSort,
            inspect: { controller.inspect(item) },
            isInspected: state.inspectedPullRequestID == item.id
        )
        .padding(.vertical, 3)
    }

    // MARK: - Status bar

    /// The symbols the rows on screen are using. Empty for the lists that
    /// have none, which is what keeps the bar quiet elsewhere.
    private var legendSymbols: [LegendSymbol] {
        switch state.sidebarSelection {
        case .pullRequests: PullRequestLegend.symbols(for: state.selectedPullRequests)
        case .myPullRequests: PullRequestLegend.symbols(for: state.selectedAuthoredPullRequests)
        case .mentions, .dashboard, .settings: []
        }
    }

    /// Finder-style status bar: the totals, the legend for the list on
    /// screen, and when it was last checked.
    private var statusBar: some View {
        HStack(spacing: 12) {
            Label("\(state.visiblePullRequests.count)", systemImage: StatusBarTitleBuilder.pullRequestSymbol)
                .help("Reviews requested")
            Label("\(state.visibleNotifications.count)", systemImage: StatusBarTitleBuilder.mentionSymbol)
                .help("Unread mentions")

            if !legendSymbols.isEmpty {
                Divider().frame(height: 11)
                LegendBar(symbols: legendSymbols)
            }

            Spacer(minLength: 8)

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
        .monospacedDigit()
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
                SortPicker(settings: state.settings)
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
    /// Nil for lists that are read rather than navigated. Where it is bound,
    /// the list gets the arrow keys for free -- that is what moves the detail
    /// pane from the keyboard.
    var selection: Binding<Item.ID?>?
    @ViewBuilder var row: (Item) -> Row

    private var groupKey: ((Item) -> String)? {
        switch grouping {
        case .flat: nil
        case .byRepository: repository
        case .byType: type
        }
    }

    var body: some View {
        if let selection {
            List(selection: selection) { content }
        } else {
            List { content }
        }
    }

    /// A row, with the selection drawn quietly.
    ///
    /// The list's own highlight is the emphasised accent fill, which at the
    /// height of these rows is a slab of blue across the window. It is
    /// painted over rather than turned off, since a `List` offers no way to
    /// ask for the unemphasised look:
    ///
    /// - an opaque layer under *every* row hides the accent fill. Only
    ///   under the selected one is not enough: a click paints the row
    ///   before the binding it is about to set comes back, so the row
    ///   flashed blue under the pointer,
    /// - an inset rounded rectangle in AppKit's own unemphasised selection
    ///   grey marks the row without reaching the window's edges,
    /// - and the text is pinned to the label colours, because inside a
    ///   selected row SwiftUI resolves every hierarchical style to white.
    private func listRow(_ item: Item) -> some View {
        row(item)
            .tag(item.id)
            .foregroundStyle(Color(nsColor: .labelColor))
            .listRowBackground(background(selected: selection?.wrappedValue == item.id))
    }

    private func background(selected: Bool) -> some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            if selected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let groupKey {
            ForEach(RepositoryGrouping.group(items, by: groupKey)) { group in
                Section {
                    ForEach(group.items) { item in
                        listRow(item)
                    }
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
            ForEach(items) { item in
                listRow(item)
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

/// What the list is ordered by.
///
/// A menu rather than another segmented control: the toolbar already carries
/// two, and the chosen order reads better as a sentence than as a pressed
/// segment.
private struct SortPicker: View {
    @Bindable var settings: Settings

    var body: some View {
        Menu {
            // An inline picker inside the menu, so the chosen order carries a
            // checkmark instead of having to be read off the button.
            Picker("Sort by", selection: $settings.pullRequestSort) {
                ForEach(PullRequestSort.allCases, id: \.self) { sort in
                    Label(sort.label, systemImage: sort.symbolName).tag(sort)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(settings.pullRequestSort.label, systemImage: "arrow.up.arrow.down")
                // The button has to say which order is in force; a bare icon
                // would make the setting invisible until the menu is opened.
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Order the list by when pull requests were opened or last updated")
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
        // Which detail belongs here follows the sidebar, not whichever id
        // happens to be set: a pull request opened before switching to the
        // mentions is not what this pane is describing any more.
        if case .mentions = state.sidebarSelection, let item = state.inspectedNotification {
            NotificationDetailView(
                item: item,
                preview: state.previews[item.id],
                markRead: { Task { await controller.markRead(item) } },
                close: { controller.closeInspector() }
            )
        } else if let item = state.inspectedPullRequest, !state.sidebarSelection.isMentions {
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
