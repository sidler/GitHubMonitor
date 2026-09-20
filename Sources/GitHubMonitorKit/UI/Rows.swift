import SwiftUI

struct PullRequestRow: View {
    let item: PullRequestItem
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
                    // verbatim: a pull request number is an identifier, not a
                    // quantity. SwiftUI's localized interpolation renders
                    // 35442 as "35.442" on a German system.
                    Text(verbatim: "\(item.repository) #\(item.number)")
                    Text("by \(item.author)")
                    Text(RelativeTime.string(for: item.updatedAt))

                    Label(item.reviewDecision.label, systemImage: item.reviewDecision.symbolName)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(reviewTint)
                        .help(item.reviewDecision.label)

                    Label(item.checks.label, systemImage: item.checks.symbolName)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(checksTint)
                        .help(item.checks.label)

                    // Next to the status symbols rather than before the
                    // title: it is a state of the pull request, like the
                    // review and check results beside it.
                    if item.isDraft {
                        Text("DRAFT")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
        // A single click opens the detail pane; the browser is one deliberate
        // step further, since it leaves the app.
        .onTapGesture {
            if let inspect {
                inspect()
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
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
        .foregroundStyle(isInspected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .padding(.top, 1)
    }

    private var reviewTint: Color {
        switch item.reviewDecision {
        case .approved: .green
        case .changesRequested: .orange
        case .reviewRequired, .none: .secondary
        }
    }

    private var checksTint: Color {
        switch item.checks {
        case .success: .green
        case .failure: .red
        case .pending: .yellow
        case .none: .secondary
        }
    }
}

