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
    /// Nil in the menu bar panel: there is no room, and a panel over a
    /// panel is not something to offer.
    var linked: LinkedPanelContext?
    var isInspected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(url: item.authorAvatarURL, size: compact ? 22 : 26)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(compact ? .callout : .body)
                    .lineLimit(compact ? 1 : 2)

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
                        .foregroundStyle(age?.tint ?? Color.rowDetail)
                        .help(waitingHelp)

                    // A step larger than the caption text around them: at
                    // caption size the review and check results are the first
                    // thing a reviewer looks for and the hardest to pick out.
                    Label(item.reviewDecision.label, systemImage: item.reviewDecision.symbolName)
                        .labelStyle(.iconOnly)
                        .font(.body)
                        .foregroundStyle(item.reviewDecision.tint)
                        .help(item.reviewDecision.label)

                    Label(item.checks.label, systemImage: item.checks.symbolName)
                        .labelStyle(.iconOnly)
                        .font(.body)
                        .foregroundStyle(item.checks.tint)
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
                            .foregroundStyle(item.mergeStatus.tint)
                            .help(item.mergeStatus.label)
                    }

                    // How far the review has got. The decision symbol before
                    // it says what the pull request still needs; these say
                    // how many people it is waiting on, which is the
                    // difference between nearly done and not started.
                    ForEach(item.reviews.entries, id: \.kind) { entry in
                        HStack(spacing: 2) {
                            Image(systemName: entry.kind.symbolName)
                                .font(.body)
                            Text(verbatim: "\(entry.count)")
                                .monospacedDigit()
                        }
                        .foregroundStyle(entry.kind.tint)
                        .help(entry.kind.sentence(count: entry.count))
                    }

                    // Next to the status symbols rather than before the
                    // title: it is a state of the pull request, like the
                    // review and check results beside it.
                    if item.isDraft {
                        DraftBadge()
                    }

                    // Last, because it is the only one that answers a
                    // question about something other than this row.
                    if let linked {
                        LinkBadge(
                            context: linked,
                            links: item.links.filter { $0.kind == .closes },
                            unshown: linked.state.unshownLinks(of: item)
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.rowDetail)
                // Truncate instead of wrapping: in a narrow column a wrapping
                // meta line turns into a stack of fragments like "arte-
                // meon/" that reads far worse than an ellipsis.
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let inspect {
                actions(inspect: inspect)
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
