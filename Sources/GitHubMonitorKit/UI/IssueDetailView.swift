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
    /// Where to read this repository's labels and write a change. Nil
    /// leaves the labels as something to read.
    var labelling: PaneWriting?

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
                        SubIssueSection(
                            parentRepository: item.repository,
                            detail: detail,
                            linked: linked
                        )
                            // Its own identity per issue, so a list
                            // unfolded on one epic does not open the next
                            // one already unfolded.
                            .id(item.id)
                        text(of: detail)
                        thread(of: detail)
                    case .failed(let message):
                        VStack(alignment: .leading, spacing: 8) {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Ink.orange)
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
                ItemNumberLabel(repository: item.repository, number: item.number)
                Text("by \(item.author)")
                Text(RelativeTime.string(for: item.createdAt))
                    .help("Opened \(RelativeTime.absolute(item.createdAt))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // First of the three lines under the title: what this issue
            // is part of comes before what answers it and what it is
            // tagged with, because it is the one that changes how the rest
            // is read.
            if case .loaded(let detail) = detail, let parent = detail.parent {
                ParentIssueLine(
                    parent: parent,
                    childRepository: item.repository,
                    linked: linked
                )
                // Its own identity per issue, like the section below:
                // the preview popover lives in a `@StateObject` inside
                // it, and without this it stays open across a move to
                // another issue, showing a parent nobody asked for.
                .id(item.id)
            }

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

            // The pane's own list where it has arrived, the row's until
            // then: the row keeps only what fits a line, so an issue with
            // a dozen labels was showing ten of them here too.
            let loaded: [IssueLabel] = {
                guard case .loaded(let detail) = detail else { return [] }
                return detail.labels
            }()
            let labels = loaded.isEmpty ? item.labels : loaded
            if item.type != nil || !labels.isEmpty || item.milestone != nil || labelling != nil {
                // Wrapping, unlike the row's single line: here there is room
                // to show every label, and which ones an issue carries is
                // part of what the pane is for.
                if let labelling {
                    LabelEditor(
                        editing: labelling,
                        repository: item.repository,
                        itemID: item.id,
                        isPullRequest: false,
                        current: labels
                    ) { open in
                        chips(labels, open: open)
                    }
                } else {
                    chips(labels, open: nil)
                }
            }
        }
        .padding(14)
    }

    /// What the item is marked with, all of it on as many lines as it
    /// takes. Unlike the row's single line: here there is room, and which
    /// ones an issue carries is part of what the pane is for.
    /// The type, the labels and the milestone, wrapping as one line of
    /// chips -- but only the labels and the tag open the picker.
    ///
    /// An issue's type and its milestone are not labels: GitHub will not
    /// set them with the mutation behind this, and they are not in the
    /// repository's list of labels. Drawn alike and clickable alike,
    /// they read as labels that the picker then refuses to show, which
    /// is how "Epic" came to look like a label nobody could find.
    private func chips(_ labels: [IssueLabel], open: (() -> Void)?) -> some View {
        FlowRow(spacing: 4) {
            if let type = item.type {
                IssueTypeChip(type: type)
            }
            ForEach(labels) { label in
                if let open {
                    LabelOpener(open: open) { LabelChip(label: label) }
                } else {
                    LabelChip(label: label)
                }
            }
            if let milestone = item.milestone {
                Label(milestone, systemImage: "flag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let open {
                LabelOpener(open: open) { LabelTag() }
            }
        }
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

    private func thread(of detail: IssueDetail) -> some View {
        ConversationView(comments: detail.comments, total: detail.totalComments)
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

        // No width is not a width to lay out in -- it is the layout engine
        // asking how small this is allowed to get. The children are then
        // measured unconstrained rather than squeezed to nothing, since a
        // chip asked to fit in no width reports the height of its text set
        // one letter per line.
        guard width > 0 else {
            return Self.size(
                of: subviews.map { $0.sizeThatFits(.unspecified) },
                width: width,
                spacing: spacing
            )
        }

        return Self.size(
            of: subviews.map { measure($0, within: width) },
            width: width,
            spacing: spacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { measure($0, within: bounds.width) }
        var y = bounds.minY
        for line in Self.lines(of: sizes, width: bounds.width, spacing: spacing) {
            var x = bounds.minX
            for index in line.indices {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(sizes[index])
                )
                x += sizes[index].width + spacing
            }
            y += line.height + spacing
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

    /// One line of the flow: which children are on it, and how big it is.
    struct Line: Equatable, Sendable {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// How children of these sizes pack into lines at this width.
    ///
    /// Static, and over plain sizes rather than subviews, so the packing
    /// can be asked questions without a view hierarchy -- including the one
    /// that mattered, which is what it claims when there is no width.
    static func lines(of sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()

        for (index, size) in sizes.enumerated() {
            let item = width.isFinite ? min(size.width, max(width, 0)) : size.width
            let needed = current.indices.isEmpty ? item : current.width + spacing + item
            if needed > width, !current.indices.isEmpty {
                lines.append(current)
                current = Line()
            }
            current.width = current.indices.isEmpty ? item : current.width + spacing + item
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }

        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }

    /// What the whole flow measures at that width.
    ///
    /// At no width it is one line tall, not one line per child. Laying out
    /// in no width is what produces a child per line, and answering with
    /// *that* height is how a strip of twenty-two linked pull requests told
    /// the issue pane it could not be drawn in less than two thousand
    /// points -- a minimum AppKit honours by making the window that tall,
    /// which it did, off the bottom of the screen. Measured through a split
    /// view: 2067 points of window before, 680 after, and the same pane
    /// with a hundred and twenty paragraphs of description and no chips had
    /// never moved it at all.
    ///
    /// One line is the honest answer to "how small": the whole point of
    /// this layout is that it adapts, and where it cannot, it gives way
    /// like everything else on the line.
    static func size(of sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> CGSize {
        guard !sizes.isEmpty else { return .zero }
        guard width > 0 else {
            return CGSize(width: 0, height: sizes.map(\.height).max() ?? 0)
        }

        let lines = lines(of: sizes, width: width, spacing: spacing)
        let height = lines.map(\.height).reduce(0, +)
            + spacing * CGFloat(max(0, lines.count - 1))
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: min(width, max(widest, 0)), height: height)
    }
}
