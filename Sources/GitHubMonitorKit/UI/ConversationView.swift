import SwiftUI

/// What was said about an issue or a pull request, as opposed to about a
/// line of it.
///
/// One view for both panes. They ask GitHub the same question in the same
/// words and show the answer the same way; the only thing that ever
/// differed was that the pull request pane counted the replies and then
/// had nothing to show, which made the tab GitHub itself calls the
/// conversation the one thing this app would not let you read.
struct ConversationView: View {
    let comments: [IssueComment]
    /// How many there are in all. The panes ask for the last few, and a
    /// thread that has been running for a month has more.
    let total: Int

    /// How many are on GitHub and not here.
    private var older: Int { max(0, total - comments.count) }

    var body: some View {
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(total == 1 ? "1 comment" : "\(total) comments")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    // Say what is missing rather than quietly showing the
                    // tail as if it were the whole thread.
                    if older > 0 {
                        Text("\(older) older on GitHub")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            AvatarView(url: comment.avatarURL, size: 18)
                            Text(comment.author).font(.caption.weight(.medium))
                            Text(RelativeTime.string(for: comment.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help(RelativeTime.absolute(comment.createdAt))
                        }
                        MarkdownText(source: comment.body)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}
