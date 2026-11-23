import AppKit
import SwiftUI

/// What was said about the pull request rather than about a line of it,
/// and somewhere to say more.
///
/// A diff answers the question "what changed"; this answers "what did
/// anybody make of it". Both used to be true only in a browser: the
/// conversation tab was counted in the pane and shown nowhere, and the
/// sentence somebody wrote when they sent a review -- which hangs on no
/// line, so no file could carry it -- was read nowhere at all.
struct ConversationContent: Equatable {
    /// The conversation tab, oldest last, as the detail read them.
    var comments: [IssueComment] = []
    /// What reviewers wrote when they sent their reviews.
    var summaries: [ReviewSummary] = []
    /// How many of the conversation are on GitHub and not here.
    var olderComments: Int = 0
    /// Every remark hung on a line of the diff, under the name this diff
    /// knows the file by.
    ///
    /// Listed here as well as drawn in the file: a review of forty files
    /// hides its four conversations in four places, and the only way to
    /// find them was to open each file and look. This page is where they
    /// can all be counted, read in one pass, and stepped into.
    var threads: [ReviewThread] = []

    var isEmpty: Bool { comments.isEmpty && summaries.isEmpty && threads.isEmpty }
    /// What the tree puts beside the entry: everything this page lists.
    var count: Int { comments.count + summaries.count + threads.count }
}

/// How the page writes the two things it can write.
///
/// Both are held with the review rather than sent as they are typed, the
/// same as every other box in a diff: one press sends what somebody
/// wrote while reading.
struct WholeReviewWriting {
    /// What the review says about the whole pull request.
    let setBody: (String) -> Void
    /// A remark for the conversation tab, which is not a review.
    let setNote: (String) -> Void
}

/// The page behind the last entry in the file tree.
struct ConversationPage: View {
    let content: ConversationContent
    /// Sends the diff to the file a conversation hangs in. Nil where
    /// there is nowhere to send it.
    var jump: ((ReviewThread) -> Void)?
    /// What has been written and not sent, so the boxes open holding it.
    let draft: ReviewDraft?
    /// Nil where the diff is a reader: a pull request that has left the
    /// lists can be read and not written to.
    let writing: WholeReviewWriting?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            said
            if !content.threads.isEmpty { onTheDiff }
            if let writing { boxes(writing) }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - What was said

    @ViewBuilder
    private var said: some View {
        if content.isEmpty {
            Text("Nothing has been said about this pull request as a whole.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                // The verdicts first and the conversation after: a review
                // summary is about the diff that was just read, which is
                // what somebody arriving at the end of it is holding.
                //
                // Headed, both of them. Without the headings this page
                // was two runs of remarks that looked alike and reached
                // GitHub by different routes, and the boxes below had no
                // way to say which of the two they were feeding.
                if !content.summaries.isEmpty {
                    Text("Said with a review")
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(content.summaries) { summary in
                    entry(
                        author: summary.author,
                        avatar: summary.avatarURL,
                        when: summary.submittedAt,
                        body: summary.body
                    ) {
                        Label(summary.state.label, systemImage: summary.state.symbolName)
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(tint(summary.state))
                    }
                }

                if !content.summaries.isEmpty, !content.comments.isEmpty {
                    Divider()
                }

                if !content.comments.isEmpty {
                    HStack(spacing: 6) {
                        Text("Said on its own")
                            .font(.subheadline.weight(.semibold))
                        if content.olderComments > 0 {
                            // Say what is missing rather than passing the
                            // tail off as the whole thread.
                            Text("\(content.olderComments) older on GitHub")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(content.comments) { comment in
                    entry(
                        author: comment.author,
                        avatar: comment.avatarURL,
                        when: comment.createdAt,
                        body: comment.body
                    ) { EmptyView() }
                }
            }
        }
    }

    // MARK: - What was said on the diff

    /// Every conversation hung on a line, in the order the files run,
    /// with a way into each.
    ///
    /// Open ones first within a file. A settled conversation is a
    /// question that has been answered; an open one is the reason this
    /// list is being read.
    private var onTheDiff: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(spacing: 6) {
                Text("Said on the diff")
                    .font(.subheadline.weight(.semibold))
                Text(content.threads.count == 1
                    ? "1 conversation" : "\(content.threads.count) conversations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(ConversationIndex.files(of: content.threads), id: \.path) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.path)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    ForEach(group.threads) { thread in
                        threadRow(thread)
                    }
                }
            }
        }
    }

    private func threadRow(_ thread: ReviewThread) -> some View {
        IndexedThread(thread: thread, jump: jump)
    }

    private func entry<Badge: View>(
        author: String,
        avatar: URL?,
        when: Date?,
        body: String,
        @ViewBuilder badge: () -> Badge
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                AvatarView(url: avatar, size: 18)
                Text(author).font(.caption.weight(.medium))
                if let when {
                    Text(RelativeTime.string(for: when))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(RelativeTime.absolute(when))
                }
                badge()
            }
            MarkdownText(source: body)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(_ state: ReviewState) -> Color {
        switch state {
        case .approved: Ink.green
        case .changesRequested: Ink.red
        case .commented, .dismissed: Ink.gray
        case .pending: Ink.gray
        }
    }

    // MARK: - What can still be said

    /// Two boxes, because GitHub keeps two things apart and so should
    /// this: a review's own summary goes out as part of the review and
    /// notifies as one, and a conversation remark is said to everybody
    /// reading the pull request whatever the verdict turns out to be.
    private func boxes(_ writing: WholeReviewWriting) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()

            WholeReviewBox(
                title: "Say it with this review",
                prompt: "Goes out attached to your verdict. On GitHub it appears in the "
                    + "conversation under Approved or Changes requested, and notifies as "
                    + "a review.",
                text: draft?.body ?? "",
                write: writing.setBody
            )

            WholeReviewBox(
                title: "Say it on its own",
                prompt: "Goes out beside the review, not inside it. On GitHub it appears "
                    + "in the conversation as a plain comment, with no verdict on it.",
                text: draft?.conversation ?? "",
                write: writing.setNote
            )

            Text("Both are kept here until you press Comment, Request changes or Approve.")
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
    }
}

/// One of the two boxes, with the formatting bar the rest of the diff's
/// boxes carry.
///
/// Its own text rather than the draft's directly: the draft is rewritten
/// on every keystroke and handed back through the window, and binding
/// straight to it put the caret back to the start of the line.
private struct WholeReviewBox: View {
    let title: String
    let prompt: String
    let text: String
    let write: (String) -> Void

    @StateObject private var typed = TypedText()
    @StateObject private var caret = CaretState()
    @StateObject private var previewing = ViewFlag()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(prompt)
                .font(.caption)
                .foregroundStyle(.secondary)

            MarkdownBar(
                text: $typed.text,
                caret: caret,
                previewing: Binding(
                    get: { previewing.isOn },
                    set: { previewing.isOn = $0 }
                )
            )

            if previewing.isOn {
                ScrollView {
                    MarkdownText(
                        source: typed.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty ? "*Nothing written yet.*" : typed.text,
                        overflowNote: ""
                    )
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 5)
                }
                .frame(minHeight: 60)
                .background(paper)
                .overlay(edge)
            } else {
                CommentTextView(
                    text: $typed.text,
                    caret: caret,
                    fontSize: NSFont.preferredFont(forTextStyle: .callout).pointSize
                )
                .background(paper)
                .overlay(edge)
            }
        }
        // Filled once, from what was written before this page was opened.
        // Not on every pass: the draft comes back through the window a
        // beat after each keystroke, and assigning it again would undo
        // whatever was typed in between.
        .onAppear { if typed.text.isEmpty { typed.text = text } }
        .onChange(of: typed.text) { _, written in write(written) }
    }

    private var paper: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color(nsColor: .textBackgroundColor))
    }

    private var edge: some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
    }
}

/// The conversations on a diff, arranged for reading in one pass.
enum ConversationIndex {
    struct Group {
        let path: String
        let threads: [ReviewThread]
    }

    /// Grouped by file, files in the order the conversations arrive --
    /// which is the order the diff puts them in -- and within a file the
    /// open ones first, then by the line they hang on.
    ///
    /// Open first because a settled conversation is a question that has
    /// been answered, and this list is read to find the ones that have
    /// not been.
    static func files(of threads: [ReviewThread]) -> [Group] {
        var order: [String] = []
        var buckets: [String: [ReviewThread]] = [:]
        for thread in threads {
            if buckets[thread.path] == nil { order.append(thread.path) }
            buckets[thread.path, default: []].append(thread)
        }
        return order.map { path in
            Group(path: path, threads: sorted(buckets[path] ?? []))
        }
    }

    static func sorted(_ threads: [ReviewThread]) -> [ReviewThread] {
        threads.sorted { lhs, rhs in
            lhs.isResolved == rhs.isResolved
                ? (lhs.anchorLine ?? .max) < (rhs.anchorLine ?? .max)
                : !lhs.isResolved
        }
    }
}

/// One conversation in the index: folded to a line, or opened to every
/// word of it.
///
/// Opened to begin with unless it is settled, which is the rule the diff
/// itself follows -- a conversation nobody has answered is the reason
/// this page is being read, and reading it should not cost a press. The
/// preview it used to show was the first line of the first remark and no
/// more, so a question whose point was in its second sentence looked
/// like a question about nothing.
private struct IndexedThread: View {
    let thread: ReviewThread
    let jump: ((ReviewThread) -> Void)?

    @StateObject private var fold: ThreadFold

    init(thread: ReviewThread, jump: ((ReviewThread) -> Void)?) {
        self.thread = thread
        self.jump = jump
        _fold = StateObject(wrappedValue: ThreadFold(isResolved: thread.isResolved))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if fold.isExpanded { remarks }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
    }

    /// The line it hangs on and what it is about, pressable to fold.
    ///
    /// The fold is on the text and the jump is on the chevron: one of
    /// them reads the conversation where it stands and the other leaves
    /// this page for the code, and a row that did both on one press
    /// would do the wrong one half the time.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { fold.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: fold.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    // Where it hangs, which is what tells two
                    // conversations on one file apart.
                    Text(thread.anchorLine.map { "Line \($0)" } ?? "No line")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        // Folded, the one line it used to show. Open, the
                        // remarks below say it better than a preview can.
                        if !fold.isExpanded {
                            Text(thread.preview)
                                .font(.callout)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        HStack(spacing: 6) {
                            if let opener = thread.comments.first?.author {
                                Text(opener)
                            }
                            Text(thread.summary)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(fold.isExpanded ? "Fold this conversation away" : "Read the whole conversation")

            if thread.isResolved {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Ink.green)
                    .help("Resolved")
            }

            Button { jump?(thread) } label: {
                Image(systemName: "chevron.right.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .disabled(jump == nil)
            .help("Go to this conversation in \(thread.path)")
            .accessibilityLabel("Go to \(thread.path), line "
                + (thread.anchorLine.map(String.init) ?? "unknown"))
        }
    }

    /// Every remark in it, not the first line of the first one.
    private var remarks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(thread.comments) { comment in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        AvatarView(url: comment.avatarURL, size: 16)
                        Text(comment.author).font(.caption.weight(.medium))
                        Text(RelativeTime.string(for: comment.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(RelativeTime.absolute(comment.createdAt))
                    }
                    MarkdownText(source: comment.body)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Lined up under the preview the fold replaced, so the column of
        // line numbers stays a column.
        .padding(.leading, 78)
    }
}
