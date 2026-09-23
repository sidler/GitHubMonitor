import SwiftUI

/// The detail pane for a notification: the message behind the headline.
///
/// The window shows this instead of expanding the row in place. An expanded
/// row pushed everything below it down the list, so reading one message cost
/// the reader their place in the others; the pane leaves the list still.
struct NotificationDetailView: View {
    let item: NotificationItem
    let preview: PreviewState?
    /// The conversation behind it: the description and the end of the
    /// comments, which is where a mention actually lives.
    let thread: IssueDetailState?
    /// Who to look for in those comments.
    let viewer: String?
    let reload: () -> Void
    let markRead: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    conversation
                    facts
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }

            footer
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(4)
                    .textSelection(.enabled)
                Spacer(minLength: 6)
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.accessoryBar)
                .help("Close details")
            }

            HStack(spacing: 6) {
                // The sender is only known once the comment has been read,
                // so the line is written to read sensibly without them.
                if let author = preview?.preview?.author {
                    AvatarView(url: author.avatarURL, size: 18)
                    Text("by \(author.login)")
                } else {
                    Image(systemName: item.symbolName)
                        .help(item.subjectType)
                }
                Text(item.repository)
                Text(RelativeTime.string(for: item.updatedAt))
                    .help(RelativeTime.absolute(item.updatedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var footer: some View {
        BottomBar {
            HStack {
                if let url = NotificationLink.browserURL(for: item) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open on GitHub", systemImage: "arrow.up.forward.square")
                    }
                }

                Spacer()

                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload the conversation")

                Button(action: markRead) {
                    Label("Mark as read", systemImage: "envelope.open")
                }
                // Marking read also clears it from the GitHub web inbox.
                .help("Marks the thread read on GitHub, not just here")
            }
            .buttonStyle(.accessoryBar)
        }
    }

    // MARK: - Body

    /// The description and then the comments, oldest of those kept first, so
    /// the thread reads downwards the way it does on GitHub.
    @ViewBuilder
    private var conversation: some View {
        switch thread {
        case .loaded(let thread):
            if !thread.body.isEmpty {
                section("Description") {
                    MarkdownText(source: thread.body)
                }
            }

            if thread.comments.isEmpty {
                Text("No comments on this one yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                section(
                    thread.totalComments == 1 ? "1 comment" : "\(thread.totalComments) comments",
                    trailing: thread.olderComments > 0
                        ? "\(thread.olderComments) older on GitHub"
                        : nil
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(thread.comments) { comment in
                            self.comment(comment)
                        }
                    }
                }
            }

        case .loading, nil:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading the conversation…").foregroundStyle(.secondary)
            }
            .font(.callout)

        case .failed(let error):
            // The single message the notification points at is still worth
            // showing when the conversation cannot be read -- a commit
            // comment has no conversation at all.
            message
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func comment(_ comment: IssueComment) -> some View {
        let isMention = viewer.map(comment.mentions) ?? false

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                AvatarView(url: comment.avatarURL, size: 18)
                Text(comment.author).font(.caption.weight(.medium))
                Text(RelativeTime.string(for: comment.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(RelativeTime.absolute(comment.createdAt))

                if isMention {
                    // The reason this thread is in the list at all: without
                    // it the mention is one comment among twenty.
                    Text("mentions you")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            MarkdownText(source: comment.body)
        }
        .padding(.leading, isMention ? 8 : 0)
        .overlay(alignment: .leading) {
            if isMention {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
    }

    @ViewBuilder
    private func section(
        _ title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    /// The single message the notification points at.
    ///
    /// The fallback: shown when the conversation cannot be read, which is
    /// the case for the subjects that have none -- a commit, a release.
    @ViewBuilder
    private var message: some View {
        switch preview {
        case .loading, nil:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading message…").foregroundStyle(.secondary)
            }
            .font(.callout)
        case .loaded(let preview):
            if let body = preview.body {
                MarkdownText(source: body)
            } else {
                Text("This notification has no message body.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    /// Why this thread is in the list at all, which is the question a
    /// notification raises and its title rarely answers.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why you got this")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Label(item.reason.label, systemImage: "bell")
                .font(.callout)
            Label(item.subjectType, systemImage: item.symbolName)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
