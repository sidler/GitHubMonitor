import SwiftUI

/// The detail pane for an issue: what it asks for, and what has been said
/// about it since.
struct IssueDetailView: View {
    let item: IssueItem
    let detail: IssueDetailState?
    let reload: () -> Void
    let close: () -> Void
    /// What the linked-pull-request panel needs. Nil leaves the pane
    /// without one.
    var linked: LinkedPanelContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch detail {
                    case .loading, nil:
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading issue…").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    case .loaded(let detail):
                        text(of: detail)
                        thread(of: detail)
                    case .failed(let message):
                        VStack(alignment: .leading, spacing: 8) {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.callout)
                            Button("Try again", action: reload)
                                .controlSize(.small)
                        }
                    }
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
                AvatarView(url: item.authorAvatarURL, size: 18)
                Text(verbatim: "\(item.repository) #\(item.number)")
                Text("by \(item.author)")
                Text(RelativeTime.string(for: item.createdAt))
                    .help("Opened \(RelativeTime.absolute(item.createdAt))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Above the labels rather than below: the pull request that
            // answers an issue is a bigger fact about it than what it is
            // tagged with.
            if let linked {
                LinkChipRow(
                    context: linked,
                    links: linked.state.links(of: item),
                    unshown: linked.state.unshownLinks(of: item)
                )
            }

            if item.type != nil || !item.labels.isEmpty || item.milestone != nil {
                // Wrapping, unlike the row's single line: here there is room
                // to show every label, and which ones an issue carries is
                // part of what the pane is for.
                FlowRow(spacing: 4) {
                    if let type = item.type {
                        IssueTypeChip(type: type)
                    }
                    ForEach(item.labels) { label in
                        LabelChip(label: label)
                    }
                    if let milestone = item.milestone {
                        Label(milestone, systemImage: "flag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
    }

    private var footer: some View {
        BottomBar {
            HStack {
                Button {
                    NSWorkspace.shared.open(item.url)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.forward.square")
                }
                Spacer()
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload the issue")
            }
            .buttonStyle(.accessoryBar)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func text(of detail: IssueDetail) -> some View {
        if detail.body.isEmpty {
            Text("This issue was opened with a title only.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            MarkdownText(source: detail.body)
        }
    }

    @ViewBuilder
    private func thread(of detail: IssueDetail) -> some View {
        if !detail.comments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(detail.totalComments == 1 ? "1 comment" : "\(detail.totalComments) comments")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    // Say what is missing rather than quietly showing the
                    // tail as if it were the whole thread.
                    if detail.olderComments > 0 {
                        Text("\(detail.olderComments) older on GitHub")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(detail.comments) { comment in
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

/// Lays its children out in rows, wrapping when one runs out of width.
///
/// SwiftUI has no wrapping stack, and a label set is exactly the case an
/// HStack handles badly: it would push the last labels off the pane rather
/// than starting a second line.
struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, max(widest, 0)), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = measure(subviews[index], within: bounds.width)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    /// What a child is, given the room there is.
    ///
    /// Offered the row's width rather than nothing: a chip carrying a long
    /// title reports its ideal width when asked with `.unspecified`, and a
    /// row laid out from ideal widths puts a child past its own right edge
    /// instead of letting it truncate. Never wider than the row.
    private func measure(_ subview: LayoutSubview, within width: CGFloat) -> CGSize {
        guard width.isFinite else { return subview.sizeThatFits(.unspecified) }
        let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: min(size.width, width), height: size.height)
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = measure(subviews[index], within: width)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
