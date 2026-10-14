import SwiftUI

/// One conversation from a review, drawn under the line it hangs on.
///
/// Prose, not code: it wraps, it keeps the column's width, and it does not
/// travel sideways when a long line of code is scrolled. That is why the
/// patch above it is cut into pieces around these rather than having them
/// drawn inside its horizontal scroll.
struct ReviewThreadView: View {
    let thread: ReviewThread
    /// Resolved threads arrive shut. Opened by hand they stay open while
    /// the diff is up, which is the same bargain the file tree makes.
    ///
    /// An object rather than `@State`: this package builds without Xcode,
    /// where the `State` macro is not available. `Disclosure` is the same
    /// one the detail pane's folded description uses.
    @StateObject private var disclosure: Disclosure

    init(thread: ReviewThread) {
        self.thread = thread
        _disclosure = StateObject(wrappedValue: Disclosure(isExpanded: !thread.isResolved))
    }

    private var isOpen: Bool { disclosure.isExpanded }

    var body: some View {
        // A rule down the left rather than a box around everything. What
        // the box was for -- telling a remark apart from the code above
        // it -- three points of colour do as well, and they say which
        // kind of remark it is at the same time. The padding a box needs
        // on four sides is most of what made a conversation of four
        // replies taller than the hunk it was about.
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(thread.tint)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                if thread.isResolved || thread.isOutdated {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { disclosure.isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            Image(systemName: thread.isResolved ? "checkmark.circle" : "clock.arrow.circlepath")
                            Text(thread.summary)
                            Spacer(minLength: 0)
                        }
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }

                if isOpen {
                    // A hairline between replies, which the padding used
                    // to do on its own. Taking the padding out without
                    // putting something in its place ran one person's
                    // remark straight into the next one's.
                    ForEach(Array(thread.comments.enumerated()), id: \.element.id) { index, comment in
                        if index > 0 { Divider() }
                        ReviewCommentView(comment: comment)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.quaternary.opacity(0.25))
        .padding(.vertical, 2)
        // No dimming for the ones that are done. It was a flat quarter
        // off everything, text included, which is the one thing the
        // contrast of this app is not allowed to be casual about -- and
        // with a grey rule and a line naming the state, it was saying a
        // third time what was already said twice.
    }
}

/// One remark, with who made it and when.
private struct ReviewCommentView: View {
    let comment: IssueComment

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                AvatarView(url: comment.avatarURL, size: 16)
                Text(comment.author).font(.caption.weight(.medium))
                Text(RelativeTime.string(for: comment.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            // Rendered rather than printed: review comments carry code
            // fences and suggestions more often than issue bodies do, and
            // a suggested replacement shown as backticks is a suggestion
            // nobody can read.
            MarkdownText(source: comment.body, overflowNote: "")
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The threads a patch cannot hold, gathered at the file's header.
///
/// GitHub gives no line for a thread whose code has since been rewritten,
/// and guessing one would put a remark beside code that was never its
/// subject. Shut to begin with: they are history, and the file's own diff
/// is what somebody opened it to read.
struct OutdatedThreadsView: View {
    let threads: [ReviewThread]
    @StateObject private var disclosure = Disclosure()

    private var isOpen: Bool { disclosure.isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { disclosure.isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Image(systemName: "clock.arrow.circlepath")
                    Text(label)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Written against code this file no longer has")

            if isOpen {
                ForEach(threads) { thread in
                    ReviewThreadView(thread: thread)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var label: String {
        let count = threads.count
        return count == 1
            ? "1 comment on code that has since changed"
            : "\(count) comments on code that has since changed"
    }
}

