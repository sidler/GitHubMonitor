import SwiftUI

/// One issue in the list.
///
/// Built like the pull request row so the two lists read as one app, with
/// the pull request's own status symbols replaced by what an issue actually
/// has: what it is labelled, how much has been said on it, and which
/// milestone it is promised to.
struct IssueRow: View {
    let item: IssueItem
    /// Which order the list is in, so the row prints the date it is ordered
    /// on -- and, ordered by type, still prints the last activity.
    var sort: ListSort = .updated
    var compact: Bool = false
    /// Nil in the popover, where there is no detail pane to open.
    var inspect: (() -> Void)?
    /// Nil in the menu bar panel: there is no room, and a panel over a
    /// panel is not something to offer.
    var linked: LinkedPanelContext?
    /// Whether pressing a label narrows the list to it. Nil in the popover
    /// and the menu bar, where there is no list to narrow.
    var labelFiltering: LabelFiltering?
    var isInspected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(url: item.authorAvatarURL, size: compact ? 22 : 26)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(compact ? .callout : .body)
                    .lineLimit(compact ? 1 : 2)

                // Laid out as a pull request row is, so the two lists
                // read as one app: what the row *is* on the left, what it
                // is tagged with at the far right, and the counts between
                // them.
                //
                // Three claims on one line, and the order they give way in
                // matters more than the order they are drawn in. The
                // counts hold their width, the repository and the author
                // hold theirs next, and the labels -- which can run to any
                // length and say the least about which row this is -- are
                // what gets squeezed. Without saying so, a narrow column
                // squeezed the first thing it came to and left rows
                // reading "ar... by... 2..." beside five coloured dots.
                HStack(spacing: 8) {
                    identity
                        .layoutPriority(2)

                    Spacer(minLength: 6)

                    labelStrip
                        // The first thing to give way when the column is
                        // narrow: everything to its left says which issue
                        // this is and where it stands. Without saying so,
                        // a narrow column squeezed the first thing it came
                        // to and left rows reading "ar... by... 2..."
                        // beside five coloured dots.
                        .layoutPriority(0)
                }
                .font(.caption)
                .foregroundStyle(Color.rowDetail)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let inspect {
                actions(inspect: inspect)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Only in the popover; in the window the list's own selection opens
        // the detail pane, and a tap gesture would swallow the click it needs.
        .modifier(OpenIssueOnTap(url: item.url, enabled: inspect == nil))
    }

    /// Where the issue lives and who opened it: the part that is read by
    /// following the words along, and that can be any length.
    private var identity: some View {
        HStack(spacing: 8) {
            // First in the line: the type is what an issue is, and the
            // rest of the line describes where it lives.
            if let type = item.type {
                IssueTypeChip(type: type, compact: compact)
            }

            // verbatim: an issue number is an identifier, not a quantity,
            // and would otherwise be printed as "1.204".
            Text(verbatim: "\(item.repository) #\(item.number)")
            Text("by \(item.author)")
            Text(timestamp)
                .help(
                    """
                    Opened \(RelativeTime.absolute(item.createdAt)) · \
                    updated \(RelativeTime.absolute(item.updatedAt))
                    """
                )

            tallies
        }
    }

    /// What it is tagged with, which is the part that gives way first.
    @ViewBuilder
    private var labelStrip: some View {
        // Nothing at all rather than an empty stack, or a row with no
        // labels would still pay the gap before one.
        if !item.labels.isEmpty {
            HStack(spacing: 6) {
                ForEach(item.labels) { label in
                    if let labelFiltering {
                        Button {
                            labelFiltering.choose(label)
                        } label: {
                            LabelChip(label: label)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .help(
                            labelFiltering.isActive(label)
                                ? "\(label.name) \u{2014} showing only these; press again for the rest"
                                : "\(label.name) \u{2014} press to show only these"
                        )
                        .accessibilityLabel(label.name)
                        .accessibilityHint(
                            labelFiltering.isActive(label)
                                ? "Shows the rest of the list again"
                                : "Shows only the issues with this label"
                        )
                        .accessibilityAddTraits(labelFiltering.isActive(label) ? [.isSelected] : [])
                    } else {
                        LabelChip(label: label)
                    }
                }
            }
        }
    }

    /// What has happened to it and what it is promised to, packed in
    /// after the date the way a pull request row packs in its symbols.
    ///
    /// They were in slots of a fixed width for a while, to put the three
    /// of them in a column that could be read straight down. The column
    /// read well; what it cost was a reserved gap on every row that was
    /// missing one of the three, and a list where most rows have no
    /// comments is then a list of holes. Packed tight is the quieter of
    /// the two, and it is what the pull request rows beside it do.
    @ViewBuilder
    private var tallies: some View {
        if let linked {
            LinkBadge(
                context: linked,
                links: linked.state.links(of: item).filter { $0.kind == .closes },
                unshown: linked.state.unshownLinks(of: item)
            )
        }

        if item.comments > 0 {
            tally(
                "bubble.left",
                "\(item.comments)",
                help: item.comments == 1 ? "1 comment" : "\(item.comments) comments"
            )
        }

        // Green only when it is finished: an epic whose last child closed
        // is the one worth spotting in a list of sixty.
        if let progress = item.progress {
            tally(
                "list.bullet.indent",
                "\(progress.completed)/\(progress.total)",
                tint: progress.isFinished ? Ink.green : nil,
                help: "\(progress.summary), sub-issues"
            )
        }

        if let milestone = item.milestone {
            tally("flag", milestone, help: "Milestone \(milestone)")
        }
    }

    /// One of them: a symbol and its value, no wider than it needs.
    private func tally(
        _ symbol: String,
        _ value: String,
        tint: Color? = nil,
        help: String
    ) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
        }
        // A concrete colour either way, like everything else on this line:
        // inside a selected row SwiftUI resolves `.secondary` against the
        // selection and the badge comes out white.
        .foregroundStyle(tint ?? Color.rowDetail)
        .help(help)
    }

    /// The date the list is sorted on, named only when it is not the usual
    /// one -- as in the pull request rows.
    private var timestamp: String {
        let date = sort.date
        let relative = RelativeTime.string(for: item.date(for: date))
        return date == .updated ? relative : "\(date.rowPrefix) \(relative)"
    }

    private func actions(inspect: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            Button(action: inspect) {
                Image(systemName: isInspected ? "sidebar.right" : "info.circle")
            }
            .help("Show details")

            Button {
                NSWorkspace.shared.open(item.url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Open on GitHub")
        }
        .buttonStyle(.accessoryBar)
        .foregroundStyle(isInspected ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
        .padding(.top, 1)
    }
}

/// Opens an issue in the browser when the row is tapped.
private struct OpenIssueOnTap: ViewModifier {
    let url: URL
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture { NSWorkspace.shared.open(url) }
        } else {
            content
        }
    }
}
