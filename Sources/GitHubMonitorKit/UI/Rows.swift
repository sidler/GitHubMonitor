import SwiftUI

struct PullRequestRow: View {
    let item: PullRequestItem
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(url: item.authorAvatarURL, size: compact ? 22 : 26)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if item.isDraft {
                        Text("DRAFT")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                    Text(item.title)
                        .font(compact ? .callout : .body)
                        .lineLimit(compact ? 1 : 2)
                }

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
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(item.url) }
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

