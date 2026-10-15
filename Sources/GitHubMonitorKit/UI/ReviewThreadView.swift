import SwiftUI

/// One conversation from a review, drawn under the line it hangs on.
///
/// Prose, not code: it wraps, it keeps the column's width, and it does not
/// travel sideways when a long line of code is scrolled. That is why the
/// patch above it is cut into pieces around these rather than having them
/// drawn inside its horizontal scroll.
struct ReviewThreadView: View {
    let thread: ReviewThread
    /// How to answer it and settle it. Nil leaves it something to read,
    /// which is what a diff opened for a pull request that has left the
    /// lists is.
    var writing: DraftWriting?
    /// What this draft already answers it with.
    var replies: [DraftComment]
    /// Where the box is open, if it is. A plain reference rather than an
    /// observed one: whoever owns it is redrawn when it changes, and
    /// this is drawn by them.
    var target: DraftTarget?
    /// Drawn as a card at the file's margin rather than between the
    /// lines. The content is the same; what changes is that every
    /// conversation gets a header it can be shut by, and that the card
    /// around it provides the background this used to draw itself.
    var inMargin: Bool = false
    /// Resolved threads arrive shut. Opened by hand they stay open while
    /// the diff is up, which is the same bargain the file tree makes.
    ///
    /// An object rather than `@State`: this package builds without Xcode,
    /// where the `State` macro is not available. `Disclosure` is the same
    /// one the detail pane's folded description uses.
    @StateObject private var disclosure: Disclosure

    init(
        thread: ReviewThread,
        writing: DraftWriting? = nil,
        replies: [DraftComment] = [],
        target: DraftTarget? = nil,
        inMargin: Bool = false
    ) {
        self.thread = thread
        self.writing = writing
        self.replies = replies
        self.target = target
        self.inMargin = inMargin
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
                if inMargin || thread.isResolved || thread.isOutdated {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { disclosure.isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            if thread.isResolved || thread.isOutdated {
                                Image(
                                    systemName: thread.isResolved
                                        ? "checkmark.circle" : "clock.arrow.circlepath"
                                )
                            }
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

                if !isOpen, inMargin, let first = thread.comments.first {
                    // Shut, a card is still worth reading past: who said
                    // something and roughly what. One line, because the
                    // card's whole job is to cost one line until it is
                    // asked for.
                    Text(first.body)
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isOpen {
                    // The code the remark was about, for a thread that
                    // could only be put near its place rather than on it.
                    // Without this the reader has no way to tell that the
                    // line above is not the subject.
                    let context = thread.context()
                    if !context.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(context.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11).monospaced())
                                    // The last line is the one the remark
                                    // is on -- that is how GitHub cuts a
                                    // hunk -- so it is the one to read.
                                    .foregroundStyle(
                                        index == context.count - 1
                                            ? Color(nsColor: .labelColor)
                                            : Color(nsColor: .secondaryLabelColor)
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 5)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    }

                    // A hairline between replies, which the padding used
                    // to do on its own. Taking the padding out without
                    // putting something in its place ran one person's
                    // remark straight into the next one's.
                    ForEach(Array(thread.comments.enumerated()), id: \.element.id) { index, comment in
                        if index > 0 { Divider() }
                        ReviewCommentView(comment: comment)
                    }

                    if let writing, let target {
                        // What this draft has to say to it, under what
                        // has been said -- where it will appear once it
                        // is sent.
                        ForEach(replies) { reply in
                            Divider()
                            DraftRemarkView(comment: reply, writing: writing, target: target)
                        }

                        Divider()
                        if target.isReplying(to: thread.id) {
                            DraftEditorView(
                                path: thread.path,
                                line: thread.anchorLine ?? 0,
                                side: thread.side,
                                thread: thread,
                                writing: writing,
                                target: target
                            )
                        } else {
                            actions(writing)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(inMargin ? Color.clear : Color(nsColor: .quaternaryLabelColor).opacity(0.25))
        .padding(.vertical, inMargin ? 0 : 2)
        // No dimming for the ones that are done. It was a flat quarter
        // off everything, text included, which is the one thing the
        // contrast of this app is not allowed to be casual about -- and
        // with a grey rule and a line naming the state, it was saying a
        // third time what was already said twice.
    }
}

extension ReviewThreadView {
    /// What can be done to a conversation from here: answer it, and
    /// settle it.
    ///
    /// Settling goes at once while an answer waits for the review, and
    /// that is not an inconsistency: an answer is something somebody is
    /// told, and a resolved mark is bookkeeping the same click undoes.
    @ViewBuilder
    fileprivate func actions(_ writing: DraftWriting) -> some View {
        HStack(spacing: 10) {
            Button("Reply") { target?.open(reply: thread) }
            Button(thread.isResolved ? "Unresolve" : "Resolve") {
                writing.setResolved(thread, !thread.isResolved)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .buttonStyle(.accessoryBar)
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
/// Only the ones GitHub gives no number for in either file now. A thread
/// whose code has since been rewritten keeps the line it was written
/// against and stands there with its own few lines of code; these are the
/// remainder, which have nothing to stand on at all. Shut to begin with:
/// the file's own diff is what somebody opened it to read.
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
            .help("Written against a line GitHub no longer finds, in either version")

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
            ? "1 comment GitHub cannot place in this file"
            : "\(count) comments GitHub cannot place in this file"
    }
}

