import SwiftUI

struct PullRequestRow: View {
    let item: PullRequestItem
    /// Which order the list is in, so the row prints the date it is
    /// ordered on.
    var sort: ListSort = .updated
    /// How long a review may wait before the timestamp says so. Nil leaves
    /// every row in the ordinary colour -- the popover takes it that way,
    /// where there is no room for a second meaning.
    var aging: (agingDays: Int, overdueDays: Int)?
    var compact: Bool = false
    /// Nil in the popover, where there is no detail pane to open.
    var inspect: (() -> Void)?
    /// Opens the review window for this one. Nil in the popover, which
    /// has no window to put one beside.
    var review: (() -> Void)?
    /// Nil in the menu bar panel: there is no room, and a panel over a
    /// panel is not something to offer.
    var linked: LinkedPanelContext?
    /// Whether pressing a label narrows the list to it. Nil in the popover
    /// and the menu bar, where there is no list to narrow.
    var labelFiltering: LabelFiltering?
    /// Set by the list on the row it has selected. The colours stand
    /// down there, because none of them can be read on the accent fill.
    @Environment(\.rowIsSelected) private var isRowSelected
    @Environment(\.controlActiveState) private var controlActive

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(url: item.authorAvatarURL, size: compact ? 22 : 26)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(compact ? .callout : .body)
                    .lineLimit(compact ? 1 : 2)

                HStack(spacing: 8) {
                    identity
                        // Everything that says which pull request this is
                        // and where it stands holds its width; the labels
                        // beside it are what gives way. Said with a raised
                        // priority rather than a lowered one: zero is the
                        // default, so marking only the labels said nothing
                        // at all and a narrow column truncated the
                        // repository and the author instead.
                        .layoutPriority(2)

                    // No labels in the menu bar panel. It is 380 points
                    // wide and shows five rows of a list of sixty: what it
                    // is for is deciding whether to open the window, and
                    // a tag clipped to a grey sliver at the right-hand
                    // edge answers nothing while costing the width that
                    // the title and the repository were using.
                    if !compact {
                        // The labels are pushed to the far end rather than
                        // added after the symbols. The symbols are a fixed
                        // set read at a glance -- a reviewer looks for the
                        // red one -- and labels run to any length, so
                        // packed in behind them they would be what moves
                        // the symbols about from row to row.
                        Spacer(minLength: 6)

                        labelStrip
                            .layoutPriority(0)
                    }
                }
                .font(.caption)
                // Hierarchical, not a grey of its own: the list draws
                // the selected row's contents white, and a named colour
                // would stay dark on the selection.
                .foregroundStyle(.secondary)
                // Truncate instead of wrapping: in a narrow column a wrapping
                // meta line turns into a stack of fragments like "arte-
                // meon/" that reads far worse than an ellipsis.
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let review {
                actions(review: review)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Only in the popover. In the window the row belongs to a list whose
        // selection opens the detail pane, and a tap gesture there swallows
        // the click the list needs to change that selection -- which would
        // take the keyboard's place in the list away with it.
        .modifier(OpenOnTap(url: item.url, enabled: inspect == nil))
    }

    /// The date, coloured only while the wait has something to say.
    ///
    /// Otherwise it inherits the row's own quiet style, which is what
    /// turns white when the row is selected.
    private var timestampStyle: AnyShapeStyle {
        rowTint(age?.tint, selected: isRowSelected)
    }

    /// Which pull request this is and where it stands: the part that is
    /// read by following the words along, and that holds its width.
    private var identity: some View {
        HStack(spacing: 8) {
            // verbatim: a pull request number is an identifier, not a
            // quantity. SwiftUI's localized interpolation renders
            // 35442 as "35.442" on a German system.
            Text(verbatim: "\(item.repository) #\(item.number)")
            Text("by \(item.author)")
            // Coloured by how long the review has been waiting,
            // so the date answers two questions at once: when
            // something last moved, and whether it is on you.
            Text(timestamp)
                .foregroundStyle(timestampStyle)
                .help(waitingHelp)

            // A step larger than the caption text around them: at
            // caption size the review and check results are the first
            // thing a reviewer looks for and the hardest to pick out.
            Label(item.reviewDecision.label, systemImage: item.reviewDecision.symbolName)
                .labelStyle(.iconOnly)
                .font(.body)
                .foregroundStyle(rowTint(item.reviewDecision.tint, selected: isRowSelected))
                .help(item.reviewDecision.label)

            Label(item.checks.label, systemImage: item.checks.symbolName)
                .labelStyle(.iconOnly)
                .font(.body)
                .foregroundStyle(rowTint(item.checks.tint, selected: isRowSelected))
                .help(item.checks.label)

            // Only the conflict. Beside the checks, because it
            // answers the same question they do: whether this can go
            // in as it stands. A symbol on every row that merges
            // cleanly would be a column reporting the normal case,
            // and the two rows that are not normal would be harder
            // to find for it, not easier. The pane says it either
            // way, where there is one pull request and room for a
            // sentence.
            if item.mergeStatus == .conflicting {
                Label(item.mergeStatus.label, systemImage: item.mergeStatus.symbolName)
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .foregroundStyle(rowTint(item.mergeStatus.tint, selected: isRowSelected))
                    .help(item.mergeStatus.label)
            }

            // How far the review has got. The decision symbol before
            // it says what the pull request still needs; these say
            // how many people it is waiting on, which is the
            // difference between nearly done and not started.
            //
            // The window only. Each of these is a symbol and a number,
            // and three of them on a 380-point row crowded out the
            // repository and the author -- while the decision symbol
            // just before them already answers the question the panel
            // is open for, which is whether this one needs a look. The
            // detail is a click away in the window, which is what the
            // panel is a way into.
            if !compact {
                ForEach(item.reviews.entries, id: \.kind) { entry in
                    HStack(spacing: 2) {
                        Image(systemName: entry.kind.symbolName)
                            .font(.body)
                        Text(verbatim: "\(entry.count)")
                            .monospacedDigit()
                    }
                    .foregroundStyle(rowTint(entry.kind.tint, selected: isRowSelected))
                    .help(entry.kind.sentence(count: entry.count))
                }
            }

            // Next to the status symbols rather than before the
            // title: it is a state of the pull request, like the
            // review and check results beside it.
            if item.isDraft {
                DraftBadge()
            }

            // Last of the status marks, because it is the only
            // one that answers a question about something other
            // than this row.
            if let linked {
                LinkBadge(
                    context: linked,
                    links: linked.state.links(of: item).filter { $0.kind == .closes },
                    unshown: linked.state.unshownLinks(of: item)
                )
            }
        }
    }

    /// What it is tagged with, pressable where there is a list to narrow.
    @ViewBuilder
    private var labelStrip: some View {
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
                                : "Shows only the pull requests with this label"
                        )
                        .accessibilityAddTraits(labelFiltering.isActive(label) ? [.isSelected] : [])
                    } else {
                        LabelChip(label: label)
                    }
                }
            }
        }
    }

    private var age: WaitingAge? {
        guard let aging, let age = WaitingAge.of(
            item, agingDays: aging.agingDays, overdueDays: aging.overdueDays
        ) else { return nil }
        // Nothing is said about a review that has only just been asked for.
        return age == .fresh ? nil : age
    }

    private var waitingHelp: String {
        let dates = "Opened \(RelativeTime.absolute(item.createdAt))"
            + " \u{00b7} updated \(RelativeTime.absolute(item.updatedAt))"
        guard let aging, let waiting = item.waiting(),
              let age = WaitingAge.of(
                  item, agingDays: aging.agingDays, overdueDays: aging.overdueDays
              )
        else { return dates }
        return age.sentence(days: Int(waiting / 86_400)) + "\n" + dates
    }

    /// The date the list is sorted on.
    ///
    /// Named only when it is not the usual one: "updated" is what this column
    /// has always meant, and a word repeated down every row earns nothing.
    private var timestamp: String {
        let date = sort.date
        let relative = RelativeTime.string(for: item.date(for: date))
        return date == .updated ? relative : "\(date.rowPrefix) \(relative)"
    }

    /// What the two symbols at the end of a row are drawn in.
    ///
    /// Explicit rather than hierarchical, which is the one place in a row
    /// that has to be. `.accessoryBar` resolves a hierarchical style
    /// against its own control context and not against what the list has
    /// painted, so `.secondary` came out the ordinary dark grey and the
    /// symbols sat navy on the accent fill, all but invisible.
    ///
    /// So the selected row names the colour AppKit uses for text on a
    /// selection, which is white while the window has the keyboard and
    /// the ordinary label colour when it does not -- the same distinction
    /// the fill itself makes.
    private var actionStyle: AnyShapeStyle {
        if isRowSelected {
            return AnyShapeStyle(
                Color(
                    // Only the key window draws the accent fill; in any
                    // other state the selection is the quiet grey, where
                    // white would be as unreadable as navy is on blue.
                    nsColor: controlActive == .key
                        ? .alternateSelectedControlTextColor
                        : .selectedControlTextColor
                )
            )
        }
        return AnyShapeStyle(.secondary)
    }

    /// What is left at the end of a row once it is selected: the way
    /// into the diff.
    ///
    /// There used to be a "Show details" button in front of it. Selecting
    /// the row already opens the pane -- that is what selecting a row in
    /// this window means -- so the button asked for a click to do what
    /// the click had just done.
    private func actions(review: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            // The review, in this app, rather than the pull request in a
            // browser. Reading a diff is what this is for, and the row
            // had no way into it that did not go through the detail pane
            // first. GitHub is still a right-click away, which is where
            // the things this app deliberately does not do belong.
            //
            // The same symbol the pane's own Review button wears: one
            // function, one sign, or neither is recognised.
            Button(action: review) {
                Image(systemName: "rectangle.split.2x1")
                    // On the label rather than outside the button:
                    // `.accessoryBar` paints its own, and a colour set
                    // around it never reached the symbol -- which is how
                    // it came out navy on the accent fill.
                    .foregroundStyle(actionStyle)
            }
            .help("Open this for review")
        }
        .buttonStyle(.accessoryBar)
        .padding(.top, 1)
    }
}


/// Opens a pull request in the browser when the row is tapped.
///
/// A modifier because the gesture has to be absent, not merely inert, where
/// a `List` is handling clicks itself.
private struct OpenOnTap: ViewModifier {
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
