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
                    // First in the line: the type is what an issue is, and
                    // the rest of the line describes where it lives.
                    if let type = item.type {
                        IssueTypeChip(type: type, compact: compact)
                    }

                    // verbatim: an issue number is an identifier, not a
                    // quantity, and would otherwise be printed as "1.204".
                    Text(verbatim: "\(item.repository) #\(item.number)")
                    Text("by \(item.author)")
                    Text(timestamp)
                        .help(
                            """
                            Opened \(RelativeTime.absolute(item.createdAt)) · \
                            updated \(RelativeTime.absolute(item.updatedAt))
                            """
                        )

                    if item.comments > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "bubble.left")
                            Text(verbatim: "\(item.comments)")
                                .monospacedDigit()
                        }
                        .help(item.comments == 1 ? "1 comment" : "\(item.comments) comments")
                    }

                    if let milestone = item.milestone {
                        HStack(spacing: 2) {
                            Image(systemName: "flag")
                            Text(milestone).lineLimit(1)
                        }
                        .help("Milestone \(milestone)")
                    }

                    if !item.labels.isEmpty {
                        // Last in the line: labels are the part that can run
                        // to any length, so they are what gets truncated
                        // rather than the repository and the date.
                        ForEach(item.labels) { label in
                            LabelChip(label: label)
                        }
                    }
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
