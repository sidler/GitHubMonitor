import SwiftUI

/// The detail pane for a notification: the message behind the headline.
///
/// The window shows this instead of expanding the row in place. An expanded
/// row pushed everything below it down the list, so reading one message cost
/// the reader their place in the others; the pane leaves the list still.
struct NotificationDetailView: View {
    let item: NotificationItem
    let preview: PreviewState?
    let markRead: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    message
                    facts
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }

            Divider()
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
                Image(systemName: item.symbolName)
                    .help(item.subjectType)
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
        HStack {
            if let url = NotificationLink.browserURL(for: item) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.forward.square")
                }
            }

            Spacer()

            Button(action: markRead) {
                Label("Mark as read", systemImage: "envelope.open")
            }
            // Marking read also clears it from the GitHub web inbox.
            .help("Marks the thread read on GitHub, not just here")
        }
        .buttonStyle(.accessoryBar)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Body

    @ViewBuilder
    private var message: some View {
        switch preview {
        case .loading, nil:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading message…").foregroundStyle(.secondary)
            }
            .font(.callout)
        case .text(let body):
            // The pane has the room the popover did not, so the message is
            // shown whole rather than clipped to a few lines -- and as
            // Markdown, which is what it was written as.
            MarkdownText(source: body)
        case .empty:
            Text("This notification has no message body.")
                .font(.callout)
                .foregroundStyle(.secondary)
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
