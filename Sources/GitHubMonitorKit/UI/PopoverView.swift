import Combine
import SwiftUI

/// Compact overview shown under the menu bar icon: the top few items of each
/// list plus a way into the full window.
struct PopoverView: View {
    @Bindable var state: AppState
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
                        pullRequestSection
                        mentionSection
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
        // A popover is translucent by default, which drags the desktop
        // wallpaper's colour through the whole panel and makes it look murky.
        // An opaque window background keeps the contrast with the white cards.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sections

    private var pullRequestSection: some View {
        let items = state.visiblePullRequests
        // A plain stack rather than `Section`, which imposes its own generous
        // header spacing outside of a List.
        return VStack(alignment: .leading, spacing: 5) {
            SectionHeader(
                title: "Reviews requested",
                count: items.count,
                symbol: StatusBarTitleBuilder.pullRequestSymbol
            ) {
                DraftToggle(state: state)
            }

            CardList(
                items: Array(items.prefix(Self.previewLimit)),
                emptyMessage: state.draftCount > 0 && !state.settings.includeDrafts
                    ? "Nothing but drafts."
                    : "Nothing waiting for your review."
            ) { item in
                PullRequestRow(item: item, compact: true)
            }

            if items.count > Self.previewLimit {
                showAllButton(count: items.count)
            }
        }
    }

    private var mentionSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionHeader(
                title: "Unread mentions",
                count: state.notifications.count,
                symbol: StatusBarTitleBuilder.mentionSymbol
            )

            CardList(
                items: Array(state.notifications.prefix(Self.previewLimit)),
                emptyMessage: "No unread mentions."
            ) { item in
                NotificationRow(item: item, compact: true)
            }

            if state.notifications.count > Self.previewLimit {
                showAllButton(count: state.notifications.count)
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

/// Draft visibility, where it is actually needed: next to the list it changes.
private struct DraftToggle: View {
    @Bindable var state: AppState

    var body: some View {
        // With no drafts around, the control would be a no-op.
        if state.draftCount > 0 {
            Button {
                state.settings.includeDrafts.toggle()
            } label: {
                Label(
                    state.settings.includeDrafts
                        ? "Hide drafts"
                        : "Show \(state.draftCount) draft\(state.draftCount == 1 ? "" : "s")",
                    systemImage: state.settings.includeDrafts ? "eye.slash" : "eye"
                )
                .font(.caption)
            }
            .buttonStyle(.accessoryBar)
            .help("Drafts are counted in the menu bar only while shown")
        }
    }
}
