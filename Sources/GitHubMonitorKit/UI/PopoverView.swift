import Combine
import SwiftUI

/// Compact overview shown under the menu bar icon: the top few items of each
/// list plus a way into the full window.
struct PopoverView: View {
    @Bindable var state: AppState
    let controller: RefreshController
    let openMainWindow: () -> Void
    let refresh: () -> Void
    let quit: () -> Void

    private static let previewLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if state.health == .unconfigured {
                unconfiguredNotice
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if shownLists.isEmpty && !showsMentions {
                            everythingHiddenNotice
                        }
                        ForEach(shownLists) { list in
                            section(for: list)
                        }
                        if showsMentions {
                            mentionSection
                        }
                    }
                    .padding(12)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Grow with the content instead of leaving a fixed slab of
                // empty space under a short list, but stop before the popover
                // turns into a full window.
                .frame(maxHeight: 460)
            }

            Divider()
            footer
        }
        .frame(width: 380)
        // No background of its own: a popover is a panel the system draws
        // the material for, and a fill here would cover it.
    }

    // MARK: - Sections

    /// The lists left switched on for this panel, in sidebar order.
    private var shownLists: [SavedList] {
        state.lists.filter { state.settings.listVisibility.isShown($0.id, in: .popover) }
    }

    private var showsMentions: Bool {
        state.settings.listVisibility.isShown(ListVisibility.mentionsKey, in: .popover)
    }

    /// Switching every section off is a way of using the popover as a menu
    /// rather than a mistake, so this says so and stays out of the way.
    private var everythingHiddenNotice: some View {
        Text("Every list is switched off for this panel. The window and the menu bar have their own switches in settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func section(for list: SavedList) -> some View {
        switch list.content {
        case .pullRequests:
            let items = state.pullRequests(in: list)
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: list.title, count: items.count, symbol: list.symbol) {
                    DraftToggle(state: state, list: list)
                }
                CardList(
                    items: Array(items.prefix(Self.previewLimit)),
                    emptyMessage: emptyMessage(for: list, shown: items.count)
                ) { item in
                    PullRequestRow(item: item, sort: list.sort, compact: true)
                }
                if items.count > Self.previewLimit {
                    showAllButton(count: items.count)
                }
            }
        case .issues:
            let items = state.issues(in: list)
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: list.title, count: items.count, symbol: list.symbol)
                CardList(
                    items: Array(items.prefix(Self.previewLimit)),
                    emptyMessage: emptyMessage(for: list, shown: items.count)
                ) { item in
                    IssueRow(item: item, sort: list.sort, compact: true)
                }
                if items.count > Self.previewLimit {
                    showAllButton(count: items.count)
                }
            }
        }
    }

    /// Why a section is empty, which is a different question depending on
    /// whether anything was found at all.
    private func emptyMessage(for list: SavedList, shown: Int) -> String {
        let fetched = list.content == .pullRequests
            ? (state.listPullRequests[list.id] ?? []).count
            : (state.listIssues[list.id] ?? []).count
        if fetched > shown { return "Everything here is filtered out." }
        return "Nothing matches this list."
    }

    private var mentionSection: some View {
        let items = state.visibleNotifications
        return VStack(alignment: .leading, spacing: 5) {
            SectionHeader(
                title: "Unread mentions",
                count: items.count,
                symbol: StatusBarTitleBuilder.mentionSymbol
            ) {
                if !items.isEmpty {
                    Button("Mark all read") {
                        Task { await controller.markAllVisibleRead() }
                    }
                    .buttonStyle(.accessoryBar)
                    .font(.caption)
                    .help("Marks these threads read on GitHub too")
                }
            }

            CardList(
                items: Array(items.prefix(Self.previewLimit)),
                emptyMessage: state.notifications.isEmpty
                    ? "No unread mentions."
                    : "Nothing matching the selected reasons."
            ) { item in
                NotificationRow(
                    item: item,
                    preview: state.previews[item.id],
                    isExpanded: state.expandedNotificationID == item.id,
                    compact: true,
                    toggle: { controller.togglePreview(for: item) },
                    markRead: { Task { await controller.markRead(item) } }
                )
            }

            if items.count > Self.previewLimit {
                showAllButton(count: items.count)
            }
        }
    }

    private func showAllButton(count: Int) -> some View {
        Button("Show all \(count)…") { openMainWindow() }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.top, 4)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Text("GitHub Monitor").font(.headline)
            Spacer()
            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(state.health == .failing ? .red : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var unconfiguredNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: StatusBarTitleBuilder.unconfiguredSymbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No GitHub token configured")
                .font(.headline)
            Text("Add a personal access token to start monitoring.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") { openMainWindow() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footer: some View {
        HStack {
            Button {
                refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(state.loadState == .loading)

            Spacer()

            Button("Open Window") { openMainWindow() }
            Button("Quit") { quit() }
        }
        .buttonStyle(.accessoryBar)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Building blocks

/// Section title, count badge and an optional trailing control.
private struct SectionHeader<Accessory: View>: View {
    let title: String
    let count: Int
    let symbol: String
    @ViewBuilder var accessory: () -> Accessory

    init(
        title: String,
        count: Int,
        symbol: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.count = count
        self.symbol = symbol
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())

            Spacer()
            accessory()
        }
        .foregroundStyle(.secondary)
    }
}

/// Groups rows into one rounded card with hairlines between them, so a list
/// reads as a list rather than as stacked paragraphs.
private struct CardList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let emptyMessage: String
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, 10)
                    }
                    HoverRow { row(item) }
                }
            }
        }
        // An opaque control background reads as a white card in light mode
        // instead of tinting itself with whatever sits behind the popover.
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

/// View-local state without `@State`: its macro implementation ships only
/// with Xcode, and this project builds against the Command Line Tools.
/// `@StateObject` is unaffected, so it stands in wherever a view needs to
/// remember something of its own.
@MainActor
private final class HoverState: ObservableObject {
    @Published var isHovering = false
}

/// Rows are clickable, so they need to say so on hover.
private struct HoverRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @StateObject private var hover = HoverState()

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover.isHovering ? AnyShapeStyle(.selection.opacity(0.25)) : AnyShapeStyle(.clear))
            .onHover { hover.isHovering = $0 }
    }
}

/// Draft visibility, where it is actually needed: next to the list it
/// changes.
private struct DraftToggle: View {
    @Bindable var state: AppState
    let list: SavedList

    private var draftCount: Int {
        (state.listPullRequests[list.id] ?? []).count { $0.isDraft }
    }

    var body: some View {
        // With no drafts around, the control would be a no-op.
        if draftCount > 0 {
            Button {
                state.settings.includeDrafts.toggle()
            } label: {
                Label(
                    state.settings.includeDrafts
                        ? "Hide drafts"
                        : "Show \(draftCount) draft\(draftCount == 1 ? "" : "s")",
                    systemImage: state.settings.includeDrafts ? "eye.slash" : "eye"
                )
                .font(.caption)
            }
            .buttonStyle(.accessoryBar)
            .help("Drafts are counted in the menu bar only while shown")
        }
    }
}
