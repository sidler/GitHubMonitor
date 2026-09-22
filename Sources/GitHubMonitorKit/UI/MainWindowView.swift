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
            // One section per saved list, in the order they are kept in
            // settings. Nothing here knows what a list is about any more:
            // the title, the icon and the searches all come from the list.
            ForEach(state.lists) { list in
                if shown(list.id) {
                    Section(list.title) {
                        Label("All", systemImage: list.symbol)
                            .badge(state.count(of: list))
                            .tag(SidebarSelection.list(id: list.id, repository: nil))

                        ForEach(state.repositories(in: list)) { entry in
                            repositoryRow(entry)
                                .tag(SidebarSelection.list(id: list.id, repository: entry.repository))
                        }
                    }
                }
            }

            if shown(ListVisibility.mentionsKey) {
                Section("Mentions") {
                    Label("All", systemImage: StatusBarTitleBuilder.mentionSymbol)
                        .badge(state.visibleNotifications.count)
                        .tag(SidebarSelection.mentions(repository: nil))

                    ForEach(state.notificationRepositories) { entry in
                        repositoryRow(entry)
                            .tag(SidebarSelection.mentions(repository: entry.repository))
                    }
                }
            }

            Section("Analysis") {
                Label("Workload", systemImage: "chart.bar")
                    .tag(SidebarSelection.dashboard)
                Label("Trends", systemImage: "chart.xyaxis.line")
                    .tag(SidebarSelection.trends)
                Label("My Trends", systemImage: "person.crop.circle.badge.clock")
                    .tag(SidebarSelection.myTrends)
            }
        }
        .listStyle(.sidebar)
        // Settings sits on the window's bottom edge rather than at the end
        // of the list, where a new section would keep pushing it around.
        // The same bar as the other columns use, so the three bottom edges
        // stay one line.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar {
                Button {
                    state.sidebarSelection = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.accessoryBar)
                // The button cannot carry the list's selection highlight, so
                // it says which view is open in its own colour.
                .foregroundStyle(isSettingsOpen ? Color.accentColor : Color(nsColor: .labelColor))
                .help("Lists, token, filters and everything else")
            }
        }
    }

    private var isSettingsOpen: Bool {
        state.sidebarSelection == .settings
    }

    private func shown(_ key: String) -> Bool {
        state.settings.listVisibility.isShown(key, in: .window)
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
        case .list(let id, _):
            if let list = state.list(withID: id) {
                switch list.content {
                case .pullRequests: pullRequestList(list)
                case .issues: issueList(list)
                }
            } else {
                ContentUnavailableView(
                    "This list is gone",
                    systemImage: "questionmark.folder",
                    description: Text("It was deleted in settings.")
                )
            }
        case .mentions: mentionList
        case .dashboard: DashboardView(state: state, controller: controller)
        case .trends: TrendsView(state: state, controller: controller)
        case .myTrends: MyTrendsView(state: state, controller: controller)
        case .settings: SettingsView(state: state, controller: controller)
        }
    }

    /// The strip the rows scroll behind. Clear while the list sits at its top
    /// — nothing is passing behind it — and a thin material once it scrolls,
    /// so rows do not collide with the title.
    ///
    /// Drawn by hand although the system has `scrollEdgeEffectStyle`: that
    /// modifier does not reach a SwiftUI `List` on macOS, which is an
    /// NSTableView inside an NSScrollView — the same reason
    /// `onScrollGeometryChange` never fires for one. It was tried; the rows
    /// scrolled straight through the toolbar.
    private func titleBarBand(height: CGFloat) -> some View {
        Rectangle()
            .fill(state.isContentScrolled ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear))
            .frame(height: height)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: state.isContentScrolled)
    }

    // MARK: - Lists

    private func pullRequestList(_ list: SavedList) -> some View {
        let items = state.selectedPullRequests(in: list)
        return GroupedList(
            items: items,
            grouping: list.grouping,
            repository: \.repository,
            selection: $state.inspectedPullRequestID
        ) { item in
            PullRequestRow(
                item: item,
                sort: list.sort,
                inspect: { controller.inspect(item) },
                isInspected: state.inspectedPullRequestID == item.id
            )
            .padding(.vertical, 3)
        }
        // Escape puts the detail pane away, as it does everywhere else.
        .onExitCommand { controller.closeInspector() }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing in “\(list.title)”",
                    systemImage: list.symbol,
                    description: Text(
                        state.selectedDraftCount > 0 && !state.settings.includeDrafts
                            ? "Only drafts match; switch them on above to see them."
                            : "No pull request matches this list's search."
                    )
                )
            }
        }
    }

    private func issueList(_ list: SavedList) -> some View {
        let items = state.selectedIssues(in: list)
        return GroupedList(
            items: items,
            grouping: list.grouping,
            repository: \.repository,
            type: \.typeName,
            selection: $state.inspectedIssueID
        ) { item in
            IssueRow(
                item: item,
                sort: list.sort,
                inspect: { controller.inspect(item) },
                isInspected: state.inspectedIssueID == item.id
            )
            .padding(.vertical, 3)
        }
        .onExitCommand { controller.closeInspector() }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing in “\(list.title)”",
                    systemImage: list.symbol,
                    description: Text(
                        state.hiddenIssueCount > 0
                            ? "Every issue here is of a type switched off above."
                            : "No issue matches this list's search."
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

    // MARK: - Status bar

    /// The symbols the rows on screen are using. Empty for the lists that
    /// have none, which is what keeps the bar quiet elsewhere.
    private var legendSymbols: [LegendSymbol] {
        guard let list = state.selectedList else { return [] }
        switch list.content {
        case .pullRequests: return PullRequestLegend.symbols(for: state.selectedPullRequests(in: list))
        case .issues: return IssueLegend.symbols(for: state.selectedIssues(in: list))
        }
    }

    /// Finder-style status bar: the totals, the legend for the list on
    /// screen, and when it was last checked.
    private var statusBar: some View {
        HStack(spacing: 12) {
            // The same switches as the sidebar: a count for a section that
            // is not there would be a number with nothing to look at.
            ForEach(state.counts(in: .window)) { entry in
                Label("\(entry.count)", systemImage: entry.symbolName)
                    .help(entry.title)
            }

            if !legendSymbols.isEmpty {
                if !state.counts(in: .window).isEmpty {
                    Divider().frame(height: 11)
                }
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

/// Controls belonging to the list on screen, hosted in a toolbar item.
struct ToolbarControls: View {
    @Bindable var state: AppState
    let controller: RefreshController

    var body: some View {
        HStack(spacing: 10) {
            switch state.sidebarSelection {
            case .list:
                if let list = state.selectedList {
                    GroupingPicker(
                        selection: binding(list, \.grouping),
                        options: list.content.groupings
                    )
                    SortPicker(selection: binding(list, \.sort), options: list.content.sorts)

                    switch list.content {
                    case .pullRequests:
                        if state.selectedDraftCount > 0 {
                            DraftToggleControl(
                                settings: state.settings,
                                draftCount: state.selectedDraftCount
                            )
                        }
                    case .issues:
                        // Only where there is something to choose between:
                        // one type and nothing else is not a filter, it is a
                        // statement.
                        if state.selectedTypeTallies.count > 1 {
                            IssueTypeFilter(state: state, list: list)
                        }
                    }
                }
            case .mentions:
                GroupingPicker(
                    selection: Binding(
                        get: { state.settings.notificationGrouping },
                        set: { state.settings.notificationGrouping = $0 }
                    ),
                    options: ListGrouping.forNotifications
                )
                if !state.selectedNotifications.isEmpty {
                    Button("Mark all read") {
                        Task { await controller.markAllVisibleRead() }
                    }
                    .help("Marks these threads read on GitHub too")
                }
            case .dashboard, .trends, .myTrends, .settings:
                EmptyView()
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }

    /// Writes a change to one field of the list back into settings, where
    /// the lists live as one stored document.
    private func binding<Value>(
        _ list: SavedList,
        _ keyPath: WritableKeyPath<SavedList, Value>
    ) -> Binding<Value> {
        Binding(
            get: { list[keyPath: keyPath] },
            set: { value in
                var updated = list
                updated[keyPath: keyPath] = value
                state.settings.update(updated)
            }
        )
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
    @Binding var selection: ListGrouping
    let options: [ListGrouping]

    var body: some View {
        Picker("", selection: $selection) {
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
/// one, and the chosen order reads better as a sentence than as a pressed
/// segment. Which orders are offered comes from the list: only issues carry
/// a type.
private struct SortPicker: View {
    @Binding var selection: ListSort
    let options: [ListSort]

    var body: some View {
        Menu {
            // An inline picker inside the menu, so the chosen order carries a
            // checkmark instead of having to be read off the button.
            Picker("Sort by", selection: $selection) {
                ForEach(options, id: \.self) { sort in
                    Label(sort.label, systemImage: sort.symbolName).tag(sort)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(selection.label, systemImage: "arrow.up.arrow.down")
                // The button has to say which order is in force; a bare icon
                // would make the setting invisible until the menu is opened.
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Order the list by when its rows were opened or last updated")
    }
}

/// Which issue types the list shows.
///
/// A menu of switches rather than a segmented control: an organisation can
/// define any number of types, and the list of them is not known until the
/// issues arrive.
private struct IssueTypeFilter: View {
    @Bindable var state: AppState
    let list: SavedList

    private var tallies: [IssueTypeTally] { state.selectedTypeTallies }

    var body: some View {
        Menu {
            ForEach(tallies) { tally in
                Toggle(isOn: binding(for: tally.name)) {
                    Text(verbatim: "\(tally.name) (\(tally.count))")
                }
            }

            Divider()
            Button("Show all types") { setHidden([]) }
                .disabled(list.hiddenTypes.isEmpty)
        } label: {
            Label(title, systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Which issue types this list shows")
    }

    /// Says what is being left out rather than what is kept: "All types" is
    /// the state worth telling apart from every other.
    private var title: String {
        let hidden = state.hiddenIssueCount
        return hidden == 0 ? "All types" : "\(hidden) hidden"
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { !list.hiddenTypes.contains(name) },
            set: { shown in
                var hidden = list.hiddenTypes
                if shown {
                    hidden.remove(name)
                } else {
                    hidden.insert(name)
                }
                setHidden(hidden)
            }
        )
    }

    private func setHidden(_ hidden: Set<String>) {
        var updated = list
        updated.hiddenTypes = hidden
        state.settings.update(updated)
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
        } else if state.selectedList?.content == .issues, let item = state.inspectedIssue {
            IssueDetailView(
                item: item,
                detail: state.issueDetails[item.id],
                reload: { controller.reloadIssueDetail(for: item.id) },
                close: { controller.closeInspector() }
            )
        } else if case .dashboard = state.sidebarSelection, let detail = state.inspectedWorkload {
            WorkloadDetailView(
                detail: detail,
                repository: state.settings.dashboardRepository,
                close: { controller.closeInspector() }
            )
        } else if state.selectedList?.content == .pullRequests, let item = state.inspectedPullRequest {
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
