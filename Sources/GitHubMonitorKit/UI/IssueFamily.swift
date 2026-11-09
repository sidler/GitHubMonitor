import AppKit
import SwiftUI

/// The issues filed under this one, and how far through them it is.
///
/// Above the issue's own text rather than below it, which is where GitHub
/// puts it. An issue with children is usually read for the children: the
/// text is the brief, and the brief is not the thing being checked on. A
/// long brief would otherwise push every child below the fold.
struct SubIssueSection: View {
    let parentRepository: String
    let detail: IssueDetail
    /// Where a child's preview is looked up. Nil leaves the rows opening
    /// GitHub in a browser instead.
    var linked: LinkedPanelContext?

    /// How many children are shown before the rest are folded away.
    ///
    /// Most issues that have any have a handful, and folding those would
    /// be a click for nothing. An issue broken into forty is a different
    /// thing: unfolded, it buries its own description under a wall of
    /// one-liners in a pane this narrow.
    private static let shownAtFirst = 12

    @StateObject private var expanded = ViewFlag()

    var body: some View {
        if let progress = detail.progress {
            VStack(alignment: .leading, spacing: 8) {
                heading(progress)
                bar(progress)
                rows
            }
            .padding(10)
            // The same card the linked-items panel uses, so two lists of
            // related work in the same window do not read as two kinds of
            // thing.
            .background(
                Color(nsColor: .quaternaryLabelColor).opacity(0.25),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1)
            )
        }
    }

    private func heading(_ progress: SubIssueProgress) -> some View {
        HStack(spacing: 6) {
            Label(
                progress.total == 1 ? "1 sub-issue" : "\(progress.total) sub-issues",
                systemImage: "list.bullet.indent"
            )
            .font(.callout.weight(.medium))

            Spacer(minLength: 8)

            Text(progress.summary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(progress.isFinished ? Ink.green : .secondary)
        }
    }

    /// A bar as well as the count, because "6 of 11" and "6 of 60" read
    /// alike at a glance and do not mean the same thing.
    private func bar(_ progress: SubIssueProgress) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(progress.isFinished ? Ink.green : Color.accentColor)
                    .frame(width: proxy.size.width * (progress.fraction ?? 0))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Sub-issues")
        .accessibilityValue(progress.summary)
    }

    /// What is on screen: all of them once asked, the first dozen before.
    private var shown: [RelatedIssue] {
        guard !expanded.isOn, detail.subIssues.count > Self.shownAtFirst else {
            return detail.subIssues
        }
        return Array(detail.subIssues.prefix(Self.shownAtFirst))
    }

    private var folded: Int { detail.subIssues.count - shown.count }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { child in
                SubIssueRow(child: child, parentRepository: parentRepository, linked: linked)
            }

            if folded > 0 {
                Button("Show \(folded) more") { expanded.isOn = true }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.vertical, 3)
            }

            // Beside the fold rather than instead of it. A list cut at the
            // query's limit is a different thing from one folded here, and
            // it cannot be unfolded -- the rows were never fetched. Behind
            // an `else` it stayed hidden for exactly the issues that have
            // both, which are the ones where the count in the heading and
            // the rows on screen differ most.
            if detail.unlistedSubIssues > 0 {
                Text("\(detail.unlistedSubIssues) more not listed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
            }
        }
    }
}

/// One child, as a line that opens its preview.
private struct SubIssueRow: View {
    let child: RelatedIssue
    let parentRepository: String
    var linked: LinkedPanelContext?

    var body: some View {
        RelatedIssueButton(related: child, linked: linked) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: LinkedSummary.symbolName(kind: .issue, state: child.state))
                    .font(.caption)
                    .foregroundStyle(child.state.tint)
                    .frame(width: 14)

                Text(verbatim: "#\(child.number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(child.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Closed is over: it stays legible, but it should not
                    // compete with the three that still need doing.
                    .foregroundStyle(child.isClosed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

                if let type = child.type {
                    IssueTypeChip(type: type, compact: true)
                }

                // Only when it is somewhere else: the repository is the
                // parent's in all but a few cases, and printing it on
                // every line would bury the one that differs.
                if child.repository != parentRepository {
                    Text(child.repository)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .help("\(child.repository)#\(child.number) \u{00B7} \(child.state.label)")
        .accessibilityLabel("\(child.title), \(child.state.label)")
    }
}

/// The issue this one is filed under, as one line above everything else.
///
/// Above, because it is the first thing that makes sense of what follows:
/// an issue that is part of something is read differently from one that
/// stands alone, and reading it the wrong way round is the mistake the
/// line exists to prevent.
struct ParentIssueLine: View {
    let parent: RelatedIssue
    let childRepository: String
    var linked: LinkedPanelContext?

    var body: some View {
        RelatedIssueButton(related: parent, linked: linked) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.left.up")
                    .font(.caption2)
                Text("Part of")
                Image(systemName: LinkedSummary.symbolName(kind: .issue, state: parent.state))
                    .foregroundStyle(parent.state.tint)
                Text(verbatim: parent.repository == childRepository
                    ? "#\(parent.number)"
                    : "\(parent.repository)#\(parent.number)")
                    .monospacedDigit()
                Text(parent.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .help("Part of \(parent.repository)#\(parent.number) \u{00B7} \(parent.state.label)")
    }
}

/// A line about another issue, which opens that issue's preview.
///
/// The same panel the linked-pull-request chips open, rather than a
/// browser: the question a sub-issue raises is "what is that one about",
/// and the whole point of the panel is that it is answered without
/// leaving what you were reading.
private struct RelatedIssueButton<Label: View>: View {
    let related: RelatedIssue
    var linked: LinkedPanelContext?
    @ViewBuilder let label: () -> Label

    @StateObject private var panel = ViewFlag()

    var body: some View {
        Button {
            // Nowhere to look it up -- the menu bar panel, where there is
            // no room for a panel over a panel. The browser is then the
            // honest fallback rather than a click that does nothing.
            if linked == nil {
                NSWorkspace.shared.open(related.url)
            } else {
                panel.isOn = true
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .popover(isPresented: $panel.isOn, arrowEdge: .bottom) {
            if let linked {
                LinkedItemsPanel(
                    state: linked.state,
                    controller: linked.controller,
                    links: [related.link],
                    close: { panel.isOn = false }
                )
            }
        }
    }
}
