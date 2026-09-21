import SwiftUI

/// A notification with an optional, lazily fetched comment preview.
struct NotificationRow: View {
    let item: NotificationItem
    let preview: PreviewState?
    let isExpanded: Bool
    var compact: Bool = false
    /// Whether the message belongs in the row. False in the window, which
    /// has a detail pane to put it in.
    var inlinePreview: Bool = true
    let toggle: () -> Void
    let markRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            summary
            if isExpanded, inlinePreview {
                previewBody
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Only where the row is not part of a selectable list: a tap gesture
        // there swallows the click the list needs to change its selection.
        .modifier(TapToToggle(enabled: inlinePreview, toggle: toggle))
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.symbolName)
                .font(compact ? .body : .title3)
                .foregroundStyle(.secondary)
                .frame(width: compact ? 22 : 26)
                .padding(.top, 1)
                .help(item.subjectType)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(compact ? .callout : .body)
                    .lineLimit(isExpanded && inlinePreview ? 3 : (compact ? 1 : 2))
                HStack(spacing: 8) {
                    Text(item.repository)
                    Text(item.reason.label)
                    Text(RelativeTime.string(for: item.updatedAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .padding(.top, 3)
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        Group {
            switch preview {
            case .loading, nil:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                }
            case .text(let body):
                // Comment bodies are Markdown and can be long; the popover is
                // a preview, not a reader.
                Text(body)
                    .lineLimit(compact ? 6 : 12)
                    .textSelection(.enabled)
            case .empty:
                Text("This notification has no message body.")
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if let url = NotificationLink.browserURL(for: item) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.forward.square")
                }
            }

            Button(action: markRead) {
                Label("Mark as read", systemImage: "envelope.open")
            }
            // Marking read also clears it from the GitHub web inbox.
            .help("Marks the thread read on GitHub, not just here")

            Spacer()
        }
        .buttonStyle(.accessoryBar)
        .font(.caption)
    }
}

/// Opens the preview when the row is tapped.
///
/// A modifier because the gesture has to be absent, not merely inert, where
/// a `List` is handling clicks itself.
private struct TapToToggle: ViewModifier {
    let enabled: Bool
    let toggle: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture(perform: toggle)
        } else {
            content
        }
    }
}
