import SwiftUI

/// What an item points at, and what those things are about.
///
/// One panel for every place that asks the question -- the pull request
/// list, the issue list, both detail panes and the diff being read. The
/// point of it is that none of them has to be left: the diff especially,
/// where "what was this issue again" is the question that otherwise sends
/// somebody to the browser and loses the review.
struct LinkedItemsPanel: View {
    @Bindable var state: AppState
    let controller: RefreshController
    /// Shown first, above the links. Set where the panel is opened from
    /// something that is itself worth summarising -- the diff overlay,
    /// where the pull request being read is the first question.
    var lead: LinkedSummary?
    let links: [ItemLink]
    /// How many more GitHub counted than are listed here.
    var unshown: Int = 0
    let close: () -> Void

    private var closes: [ItemLink] { links.filter { $0.kind == .closes } }
    private var mentions: [ItemLink] { links.filter { $0.kind == .mentions } }

    /// Tracks a resize while it is happening, so the panel follows the
    /// hand and only the settings are written when it is let go.
    @StateObject private var resize = PanelResize()

    /// How tall the panel is when nobody has said otherwise, worked out
    /// from how many cards there will be rather than from what is in them.
    ///
    /// A popover measured from its own content takes that measurement when
    /// it opens and keeps it. The summaries are fetched at that moment, so
    /// a panel sized this way was sized from three "loading" lines and
    /// stayed that size once the summaries arrived -- which is exactly
    /// what it did. Counting the cards is known straight away.
    ///
    /// An explicit size is a different matter: the popover does follow one
    /// of those, which is what lets the corner below work at all.
    private var naturalHeight: CGFloat {
        let cards = (lead == nil ? 0 : 1) + links.count
        // One card is something being read rather than something being
        // scanned -- a sub-issue opened to find out what it says. It opens
        // at the full height, since the text below it is no longer cut
        // short and 200 points of a specification is a scrollbar.
        guard cards > 1 else { return 520 }
        let groups = (closes.isEmpty ? 0 : 1) + (mentions.isEmpty ? 0 : 1)
        let wanted = 28 + CGFloat(cards) * 172 + CGFloat(groups) * 24
        return min(max(wanted, 120), 520)
    }

    private var width: CGFloat {
        CGFloat(resize.width ?? state.settings.linkedPanelWidth)
    }

    private var height: CGFloat {
        if let dragged = resize.height { return CGFloat(dragged) }
        if let kept = state.settings.linkedPanelHeight { return CGFloat(kept) }
        return naturalHeight
    }

    var body: some View {
        scroller
            .frame(width: width, height: height)
            // A popover inherits the environment of what it springs
            // from, and what this springs from is a row that truncates
            // everything to one line. Without this the summary was a
            // single clipped sentence.
            .lineLimit(nil)
            .overlay(alignment: .bottomTrailing) { corner }
            .task(id: links.map(\.id).joined()) {
                controller.loadLinksIfNeeded(links.map(\.reference))
            }
    }

    /// The corner that resizes the panel.
    ///
    /// A corner rather than an edge: a popover has no frame of its own to
    /// take hold of, and one target that does both axes is easier to find
    /// than two that each do one. Double-clicking it gives the panel back
    /// to the cards, which is where it starts.
    private var corner: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(resize.isHovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onHover { if resize.width == nil { resize.isHovering = $0 } }
            .pointerStyle(.frameResize(position: .bottomTrailing))
            .help("Drag to resize. Double-click to fit the contents.")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        resize.isHovering = true
                        // Measured from where the hand took hold, not from
                        // where the panel is now: a drag reports how far it
                        // has come in total, so adding that to a size this
                        // same drag has already changed feeds the panel its
                        // own growth and it runs away from the pointer.
                        let from = resize.start
                            ?? CGSize(width: width, height: height)
                        resize.start = from
                        resize.width = Settings.clampedPanelWidth(
                            Double(from.width + gesture.translation.width)
                        )
                        resize.height = Settings.clampedPanelHeight(
                            Double(from.height + gesture.translation.height)
                        )
                    }
                    .onEnded { _ in
                        if let width = resize.width { state.settings.linkedPanelWidth = width }
                        if let height = resize.height { state.settings.linkedPanelHeight = height }
                        resize.start = nil
                        resize.width = nil
                        resize.height = nil
                    }
            )
            .onTapGesture(count: 2) {
                state.settings.linkedPanelWidth = Settings.defaultLinkedPanelWidth
                state.settings.linkedPanelHeight = nil
            }
    }

    private var scroller: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let lead {
                    LinkedSummaryCard(
                        state: state, controller: controller, summary: lead,
                        showsReveal: false, close: close
                    )
                }

                if !closes.isEmpty {
                    group(lead == nil ? "Linked" : "Closes", links: closes)
                }
                if !mentions.isEmpty {
                    group("Mentioned", links: mentions)
                }

                if unshown > 0 {
                    Text("and \(unshown) more linked on GitHub")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if links.isEmpty && lead == nil {
                    Text("Nothing is linked to this one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func group(_ title: String, links: [ItemLink]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(links) { link in
                LinkedRow(state: state, controller: controller, link: link, close: close)
            }
        }
    }
}

/// One link, in whatever state its lookup is in.
private struct LinkedRow: View {
    @Bindable var state: AppState
    let controller: RefreshController
    let link: ItemLink
    let close: () -> Void

    var body: some View {
        switch state.linkedSummaries[link.reference.id] {
        case .loaded(let summary):
            LinkedSummaryCard(state: state, controller: controller, summary: summary, close: close)
        case .loading, nil:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                // The number is known before anything else is, so the row
                // says which one it is waiting for.
                Text(verbatim: link.reference.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(spacing: 7) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Ink.orange)
                    .lineLimit(2)
                Button("Try again") { controller.reloadLink(link.reference) }
                    .buttonStyle(.accessoryBar)
                    .font(.caption)
            }
        // Dropped before the panel is built, so this should not arrive.
        // Drawing nothing is the same answer either way.
        case .missing:
            EmptyView()
        }
    }
}

/// The summary itself: what it is, where it stands, and enough of what it
/// says to answer the question that opened the panel.
private struct LinkedSummaryCard: View {
    @Bindable var state: AppState
    let controller: RefreshController
    let summary: LinkedSummary
    /// False for the item the panel is already about: offering to show
    /// somebody what they are looking at is not an offer.
    var showsReveal = true
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            LinkedSummaryDetails(
                state: state, controller: controller, summary: summary,
                showsReveal: showsReveal, close: close
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: summary.symbolName)
                .foregroundStyle(summary.state.tint)
                .help(summary.state.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(3)
                Text(verbatim: "\(summary.reference.id) \u{00b7} \(summary.state.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

}

/// What the summary says, without the card around it.
///
/// Its own view because two places want the same facts in different
/// surroundings: the panel, which draws them on a card, and the strip
/// beside a diff, where the same thing is a fold under a section heading.
/// Built once so a field added to one cannot go missing from the other.
struct LinkedSummaryDetails: View {
    @Bindable var state: AppState
    let controller: RefreshController
    let summary: LinkedSummary
    /// False for the item the panel is already about: offering to show
    /// somebody what they are looking at is not an offer.
    var showsReveal = true
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !summary.labels.isEmpty {
                FlowRow(spacing: 4) {
                    ForEach(summary.labels) { LabelChip(label: $0) }
                }
            }

            facts

            if summary.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Opened with a title only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // All of it. It used to stop after four blocks, on the
                // theory that the panel answers "what is this about" and
                // not "what does it say" -- but the two are the same
                // question for anything with a heading per section, and a
                // preview that stops at "Hintergrund: No response" has
                // answered nothing. The panel scrolls and can be dragged
                // taller; cutting the text was solving a problem the
                // panel already solves.
                MarkdownText(source: summary.body)
            }

            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The short facts, chosen by kind: what an issue is judged by is who
    /// is talking about it, what a pull request is judged by is whether it
    /// passes and how big it is.
    private var facts: some View {
        HStack(spacing: 10) {
            Label("by \(summary.author)", systemImage: "person")
                .labelStyle(.titleOnly)
            Text(RelativeTime.string(for: summary.updatedAt))
                .help(RelativeTime.absolute(summary.updatedAt))
            if summary.comments > 0 {
                Label("\(summary.comments)", systemImage: "bubble.left")
            }
            if let checks = summary.checks, checks != .none {
                Image(systemName: checks.symbolName)
                    .foregroundStyle(checks.tint)
                    .help(checks.label)
            }
            if let additions = summary.additions, let deletions = summary.deletions {
                Text(verbatim: "+\(additions)").foregroundStyle(Ink.green).monospacedDigit()
                Text(verbatim: "\u{2212}\(deletions)").foregroundStyle(Ink.red).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            // Only where it is actually in one of the lists. The pane shows
            // what a list holds, and an issue from a repository nobody
            // follows is not in one.
            if showsReveal, state.canReveal(summary.reference) {
                Button("Show in list") {
                    state.reveal(summary.reference)
                    close()
                }
            }
            Button {
                NSWorkspace.shared.open(summary.url)
            } label: {
                Label("Open on GitHub", systemImage: "arrow.up.forward.square")
            }
            Spacer(minLength: 0)
            Button {
                controller.reloadLink(summary.reference)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Read it again")
        }
        .buttonStyle(.accessoryBar)
        .font(.caption)
    }
}


extension LinkedSummary {
    /// A pull request already on screen, summarised from what is known
    /// about it here.
    ///
    /// Built rather than fetched: the diff overlay is opened from a row
    /// whose detail is loading beside it, and asking GitHub again for what
    /// is already in hand would spend a point to learn nothing.
    /// A draft is only a draft while it is open; a merged one is merged
    /// whatever it was drafted as.
    static func state(of item: PullRequestItem) -> State {
        switch item.state {
        case .merged: .merged
        case .closed: .closed
        case .open: item.isDraft ? .draft : .open
        }
    }

    static func local(_ item: PullRequestItem, detail: PullRequestDetail?) -> LinkedSummary {
        LinkedSummary(
            reference: item.reference,
            kind: .pullRequest,
            state: Self.state(of: item),
            title: item.title,
            author: item.author,
            authorAvatarURL: item.authorAvatarURL,
            url: item.url,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            body: detail?.body ?? "",
            comments: detail?.totalComments ?? 0,
            checks: item.checks,
            reviewDecision: item.reviewDecision,
            changedFiles: detail?.changedFiles,
            additions: detail?.additions,
            deletions: detail?.deletions
        )
    }
}

/// What a row needs to be able to open the panel.
///
/// Passed as one value because a row that cannot open it -- the menu bar
/// panel's rows, which have nothing to open a panel over -- should be able
/// to say so by leaving one thing out rather than several.
struct LinkedPanelContext {
    let state: AppState
    let controller: RefreshController
}

/// View-local state without `@State`: its macro implementation ships only
/// with Xcode, and this project builds against the Command Line Tools.
@MainActor
final class ViewFlag: ObservableObject {
    @Published var isOn = false
}

/// The chain in a row: that there is a linked issue, and which one.
///
/// Only the strong kind. A number somebody wrote in a sentence is not worth
/// a symbol in a list of forty rows, and the row has not read the
/// description anyway.
struct LinkBadge: View {
    let context: LinkedPanelContext
    let links: [ItemLink]
    let unshown: Int

    @StateObject private var panel = ViewFlag()

    var body: some View {
        if let first = links.first {
            Button {
                panel.isOn = true
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "link")
                    Text(verbatim: "\(first.reference.number)")
                        .monospacedDigit()
                    if links.count + unshown > 1 {
                        Text(verbatim: "+\(links.count + unshown - 1)")
                            .monospacedDigit()
                    }
                }
                // Green for open, purple for merged, grey for anything
                // that is over. Scanning a list of issues, the question
                // behind the number is whether the answer has landed --
                // and the number alone does not say.
                .foregroundStyle(
                    LinkedState.of(first, in: context.state)?.tint
                        ?? Color(nsColor: .secondaryLabelColor)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Drawn as text among other text, so nothing about it says it
            // can be pressed until the pointer says so.
            .pointerStyle(.link)
            .help(helpText)
            .popover(isPresented: $panel.isOn, arrowEdge: .bottom) {
                LinkedItemsPanel(
                    state: context.state,
                    controller: context.controller,
                    links: links,
                    unshown: unshown,
                    close: { panel.isOn = false }
                )
            }
        }
    }

    private var helpText: String {
        let names = links.map { link in
            guard let state = LinkedState.of(link, in: context.state) else {
                return link.reference.id
            }
            return "\(link.reference.id) \u{00b7} \(state.label)"
        }
        .joined(separator: ", ")
        guard unshown > 0 else { return "Linked to \(names)" }
        return "Linked to \(names) and \(unshown) more"
    }
}

/// Where the thing a link points at stands.
///
/// From the link itself where GitHub said so with it -- which the lists
/// now ask for, since those nodes were already being fetched -- and
/// otherwise from a summary looked up since. A number read out of prose
/// knows nothing until somebody has opened the panel on it.
@MainActor
enum LinkedState {
    static func of(_ link: ItemLink, in state: AppState) -> LinkedSummary.State? {
        if let known = link.state { return known }
        guard case .loaded(let summary) = state.linkedSummaries[link.reference.id]
        else { return nil }
        return summary.state
    }
}

/// The links written out, for a pane with room for them.
///
/// A chip each rather than one symbol: in a pane the useful thing is seeing
/// which issues without opening anything. Any of them opens the panel, and
/// the panel holds them all -- two ways of narrowing the same list would be
/// two things to learn.
struct LinkChipRow: View {
    let context: LinkedPanelContext
    let links: [ItemLink]
    var unshown: Int = 0

    @StateObject private var panel = ViewFlag()

    var body: some View {
        if !links.isEmpty {
            FlowRow(spacing: 4) {
                ForEach(links) { link in
                    Button { panel.isOn = true } label: { chip(link) }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .help(help(link))
                }
                if unshown > 0 {
                    Text("+\(unshown)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .popover(isPresented: $panel.isOn, arrowEdge: .bottom) {
                LinkedItemsPanel(
                    state: context.state,
                    controller: context.controller,
                    links: links,
                    unshown: unshown,
                    close: { panel.isOn = false }
                )
            }
        }
    }

    /// Where the pull request behind this chip stands.
    ///
    /// From the link where GitHub said so with it, and otherwise from a
    /// summary already fetched -- a number read out of prose knows nothing
    /// until somebody has opened the panel on it.
    private func state(_ link: ItemLink) -> LinkedSummary.State? {
        LinkedState.of(link, in: context.state)
    }

    private func help(_ link: ItemLink) -> String {
        let name = link.title ?? link.reference.id
        guard let state = state(link) else { return name }
        return "\(name) \u{00b7} \(state.label)"
    }

    private func chip(_ link: ItemLink) -> some View {
        // Green for open, purple for merged, grey for anything that is
        // over: a number alone says a pull request answers this issue
        // without saying whether anybody has merged it, which is the
        // question being asked when the list is scanned.
        // Grey where nothing is known yet, rather than the accent: a
        // chip drawing its own wash under its own colour cannot be read,
        // whichever accent the Mac is set to.
        let tint = state(link)?.tint ?? Ink.gray
        return HStack(spacing: 3) {
            Image(systemName: link.kind == .closes ? "link" : "text.quote")
            Text(verbatim: "\(link.reference.number)")
                .monospacedDigit()
            if let title = link.title {
                Text(title).lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(tint.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
    }
}

/// What a pull request answers, written out down the strip beside the
/// diff being read.
///
/// The strip rather than the title bar's panel, which is where this used
/// to be and only there. A popover is a thing you open, read and put away;
/// the ticket is what the diff is being read *against*, and wanting it
/// beside the code for the length of a review is wanting it on the strip.
/// The panel stays -- it is the way to this from a list row, where there
/// is no strip.
struct LinkedItemsSection: View {
    let context: LinkedPanelContext
    let links: [ItemLink]
    var unshown: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ItemLink.strongestFirst(links)) { link in
                LinkedItemDisclosure(context: context, link: link)
            }
            if unshown > 0 {
                Text("and \(unshown) more linked on GitHub")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // One request for all of them, and only for the ones not already
        // in hand. Asked here rather than when a fold is opened, because
        // the fold line wants the title -- and a number read out of prose
        // has none until somebody has looked it up.
        .task(id: links.map(\.id).joined()) {
            context.controller.loadLinksIfNeeded(links.map(\.reference))
        }
    }
}

/// One linked item: a line saying which it is, and what it says folded
/// under that line.
///
/// Folded, for the reason the description beside it is: an issue body is
/// unbounded, and a specification with six headings would push the
/// branch, the checks and the reviewers off the strip. The fold line
/// carries the title, so closing it does not lose which issue this is.
struct LinkedItemDisclosure: View {
    let context: LinkedPanelContext
    let link: ItemLink

    @StateObject private var disclosure = Disclosure()

    private var summary: LinkedSummary? {
        guard case .loaded(let found) = context.state.linkedSummaries[link.reference.id]
        else { return nil }
        return found
    }

    private var state: LinkedSummary.State? { LinkedState.of(link, in: context.state) }

    var body: some View {
        DisclosureGroup(isExpanded: $disclosure.isExpanded) {
            content
                .padding(.top, 6)
                .padding(.leading, 2)
        } label: {
            // A button rather than the bare label, for the reason the
            // description's fold carries one: on macOS only the triangle
            // toggles a DisclosureGroup, which leaves the title looking
            // like a control that does nothing.
            Button { disclosure.isExpanded.toggle() } label: { fold }
                .buttonStyle(.plain)
        }
    }

    private var fold: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbolName)
                // Grey while nothing is known: a number read out of a
                // sentence is a guess until it has been looked up, and
                // green would be an answer the app does not have.
                .foregroundStyle(state?.tint ?? Color(nsColor: .tertiaryLabelColor))
            Text(verbatim: link.reference.id)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let title = summary?.title ?? link.title {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if link.kind == .mentions {
                Text("mentioned")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .help(state.map { "\(link.reference.id) \u{00b7} \($0.label)" } ?? link.reference.id)
    }

    /// What it is and where it stands, once that is known; otherwise which
    /// kind of link it is, which is all there is to go on.
    private var symbolName: String {
        guard let summary else { return link.kind == .closes ? "link" : "text.quote" }
        return summary.symbolName
    }

    @ViewBuilder
    private var content: some View {
        switch context.state.linkedSummaries[link.reference.id] {
        case .loaded(let summary):
            LinkedSummaryDetails(
                state: context.state,
                controller: context.controller,
                summary: summary,
                // Nothing to put away: this is a fold on a strip, not a
                // popover, and the strip stays where it is.
                close: {}
            )
        case .loading, nil:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Loading\u{2026}").font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(spacing: 7) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Ink.orange)
                    .lineLimit(2)
                Button("Try again") { context.controller.reloadLink(link.reference) }
                    .buttonStyle(.accessoryBar)
                    .font(.caption)
            }
        case .missing:
            EmptyView()
        }
    }
}

/// An item and what it points at, for the one place that leads with the
/// item itself: the diff, where "what is this pull request even for" is the
/// question that otherwise sends somebody to the browser.
struct LinkedSubject {
    let context: LinkedPanelContext
    let summary: LinkedSummary
    let links: [ItemLink]
    var unshown: Int = 0
}

/// The button that opens it, wearing the item's own title.
struct LinkedSubjectButton: View {
    let subject: LinkedSubject

    @StateObject private var panel = ViewFlag()

    var body: some View {
        Button {
            panel.isOn = true
        } label: {
            Label {
                Text(subject.summary.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Enough to recognise it by, not enough to push the
                    // controls beside it off the bar.
                    .frame(maxWidth: 280, alignment: .leading)
            } icon: {
                Image(systemName: "info.circle")
            }
        }
        .buttonStyle(.accessoryBar)
        .pointerStyle(.link)
        .help("What this pull request is for, and the issues it answers")
        .popover(isPresented: $panel.isOn, arrowEdge: .bottom) {
            LinkedItemsPanel(
                state: subject.context.state,
                controller: subject.context.controller,
                lead: subject.summary,
                links: subject.links,
                unshown: subject.unshown,
                close: { panel.isOn = false }
            )
        }
    }
}

/// A resize in progress.
///
/// Its own object, and its own file-private type, for the reason the diff
/// overlay's divider has one: this package builds without Xcode, where the
/// `State` macro is not available.
@MainActor
private final class PanelResize: ObservableObject {
    /// What the panel measured when the hand took hold.
    @Published var start: CGSize?
    /// Nil except while the corner is being dragged.
    @Published var width: Double?
    @Published var height: Double?
    @Published var isHovering = false
}
