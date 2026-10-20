import SwiftUI

/// The detail pane: what a reviewer wants to know before opening the browser.
struct PullRequestDetailView: View {
    let item: PullRequestItem
    let detail: DetailState?
    /// Fetched separately from the rest, so it arrives on its own schedule.
    let files: ChangedFilesState?
    let reload: () -> Void
    let close: () -> Void
    /// Opens one file's diff over the window. The pane cannot do it itself:
    /// anything it puts up is bounded by its own 400 points.
    var openDiff: (ChangedFile) -> Void = { _ in }
    /// What the linked-issue panel needs. Nil leaves the pane without one.
    var linked: LinkedPanelContext?
    /// Where to read this repository's labels and write a change. Nil
    /// leaves the labels as something to read.
    var labelling: PaneWriting?
    /// Where to ask for a merge. The same thing `labelling` is; named
    /// separately so a pane can be given one and not the other.
    var writing: PaneWriting?

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
                            Text("Loading details…").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    case .loaded(let detail):
                        branches(detail)
                        changes(detail)
                        description(detail)
                        // What was said about the pull request as a
                        // whole, as against about a line of it: the pane
                        // counted these and showed none of them, so the
                        // one objection nobody hung on a diff was the
                        // one you had to open a browser to read.
                        ConversationView(
                            comments: detail.comments, total: detail.totalComments
                        )
                        // Then how it got there, and then which files it
                        // moved.
                        if let writing, detail.commitCount > 0 {
                            CommitsSection(
                                pullRequestID: item.id,
                                total: detail.commitCount,
                                pane: writing
                            )
                        }
                        changedFiles
                        checks(detail)
                        reviewers(detail)
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

            mergeNote
            footer
        }
    }

    /// Why the merge button is grey, or why the last press merged
    /// nothing, said where the button is.
    ///
    /// It used to be said in the Branch section at the top of the pane,
    /// which is scrolled away by the time anybody is looking at the
    /// button -- so pressing it looked like pressing nothing at all. The
    /// only other explanation was a tooltip, and a tooltip has to be
    /// waited for by somebody who already suspects there is something to
    /// wait for.
    ///
    /// A refusal is the louder of the two: it answers a press. A blocker
    /// is merely the state of the pull request, and says so quietly.
    @ViewBuilder
    private var mergeNote: some View {
        if let writing {
            let refusal = writing.state.merging.message(for: item.id)
            if let note = refusal ?? MergeQuery.blocker(for: item) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(note)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(
                    refusal == nil ? Color(nsColor: .secondaryLabelColor) : Ink.orange
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(4)
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
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Directly under who opened it: what a pull request is for is
            // read before what it changes. Drawn only when there is one, so
            // the head of the pane does not grow for the many that have
            // none.
            if let linked {
                LinkChipRow(
                    context: linked,
                    links: linked.state.links(of: item),
                    unshown: linked.state.unshownLinks(of: item)
                )
            }

            // Only the pane carries these, never the row: a pull request
            // row already says more than an issue row does, and the
            // labels would be the line that broke it. Wrapping, because
            // the point of showing them here is showing all of them.
            if case .loaded(let loaded) = detail, !loaded.labels.isEmpty || labelling != nil {
                if let labelling {
                    LabelEditor(
                        editing: labelling,
                        repository: item.repository,
                        itemID: item.id,
                        isPullRequest: true,
                        current: loaded.labels
                    ) { open in
                        FlowRow(spacing: 4) {
                            ForEach(loaded.labels) { label in
                                LabelOpener(open: open) { LabelChip(label: label) }
                            }
                            LabelOpener(open: open) { LabelTag() }
                        }
                    }
                } else {
                    FlowRow(spacing: 4) {
                        ForEach(loaded.labels) { LabelChip(label: $0) }
                    }
                }
            }
        }
        .padding(14)
    }

    /// The heaviest button in the app, and the only one that puts code
    /// somewhere other people build from.
    ///
    /// What stands in the way is said rather than merely greying it out:
    /// "Merge" with no explanation, refusing to be pressed, is a worse
    /// answer than "its checks are still running".
    @ViewBuilder
    private func mergeButton(_ writing: PaneWriting) -> some View {
        let blocker = MergeQuery.blocker(for: item)
        let methods = writing.state.merging.methods(for: item.id)
        // Taken out of the state here, while the question is being drawn,
        // because by the time a button in it is pressed the state has
        // already been put back.
        let commit = writing.state.merging.commit(for: item.id)

        Button {
            Task { await writing.controller.askToMerge(item) }
        } label: {
            Label("Merge", systemImage: "arrow.triangle.merge")
        }
        .disabled(blocker != nil || writing.state.merging.isBusy)
        .help(blocker ?? "Merge this pull request")
        .confirmationDialog(
            "Merge #\(item.number) into \(detailBase)?",
            isPresented: Binding(
                get: { writing.state.merging.isConfirming(item.id) },
                set: { if !$0 { writing.controller.cancelMerge() } }
            ),
            titleVisibility: .visible
        ) {
            // One button per way this repository allows it. Where it
            // allows only one there is only one, and the question is
            // then a yes or no rather than a choice nobody has.
            if let commit {
                ForEach(methods, id: \.self) { method in
                    Button(methods.count == 1 ? method.action : method.label) {
                        Task { await writing.controller.merge(item, using: method, at: commit) }
                    }
                }
            }
            Button("Cancel", role: .cancel) { writing.controller.cancelMerge() }
        } message: {
            Text("This cannot be undone from here.")
        }
    }

    /// The branch it goes into, for the question. Empty until the detail
    /// has arrived, which is before the button can be pressed anyway.
    private var detailBase: String {
        if case .loaded(let loaded) = detail, !loaded.baseBranch.isEmpty {
            return loaded.baseBranch
        }
        return "its base branch"
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
                if let writing { mergeButton(writing) }
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload details")
            }
            .buttonStyle(.accessoryBar)
        }
    }

    // MARK: - Sections

    /// A symbol in a column of its own, so the two lines of the branch
    /// section start their text at the same place. Their glyphs are
    /// different widths, and what the eye follows down the section is the
    /// left edge of the words, not the symbols.
    private func branchSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.callout)
            .frame(width: 16, alignment: .center)
    }

    @ViewBuilder
    private func branches(_ detail: PullRequestDetail) -> some View {
        if !detail.headBranch.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        branchSymbol("arrow.triangle.branch")
                            .foregroundStyle(.secondary)
                        Text(detail.headBranch)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(detail.headBranch)
                        if !detail.baseBranch.isEmpty {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(detail.baseBranch)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .font(.callout)

                    // Under the two branches, because that is what it is
                    // about: whether the one still goes into the other. In
                    // words here -- a pane has the room the row did not --
                    // and for both answers, where a list only reports the
                    // conflict.
                    if detail.mergeStatus != .unknown {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            branchSymbol(detail.mergeStatus.symbolName)
                            Text(detail.mergeStatus.label)
                                .font(.caption)
                        }
                        .foregroundStyle(detail.mergeStatus.tint)
                    }
                }
            } header: {
                sectionTitle("Branch")
            }
        }
    }

    private func changes(_ detail: PullRequestDetail) -> some View {
        Section {
            HStack(spacing: 14) {
                statistic(
                    "\(detail.changedFiles)",
                    caption: detail.changedFiles == 1 ? "file" : "files",
                    tint: .primary
                )
                statistic("+\(detail.additions)", caption: "added", tint: Ink.green)
                statistic("−\(detail.deletions)", caption: "removed", tint: Ink.red)
                // Whichever of the two there is something to say about.
                // A pane about a diff should lead with the remarks on the
                // diff; a pull request nobody has reviewed still has a
                // conversation worth counting.
                if detail.reviewConversations > 0 {
                    statistic(
                        "\(detail.reviewConversations)",
                        caption: detail.reviewConversations == 1
                            ? "conversation" : "conversations",
                        tint: .primary
                    )
                    .help(discussion(detail))
                } else {
                    statistic(
                        "\(detail.totalComments)",
                        caption: detail.totalComments == 1 ? "comment" : "comments",
                        tint: .primary
                    )
                    .help(discussion(detail))
                }
                // Free: the detail query already asks for the newest
                // commit, and a total beside it is one more field. The
                // commits themselves are read only when somebody opens
                // the section below.
                if detail.commitCount > 0 {
                    statistic(
                        "\(detail.commitCount)",
                        caption: detail.commitCount == 1 ? "commit" : "commits",
                        tint: .primary
                    )
                }
            }
        } header: {
            sectionTitle("Changes")
        }
    }

    // MARK: - The description

    /// The author's own text, folded away.
    ///
    /// Folded because a description is unbounded: a template with four
    /// headings and a checklist would push the branch, the files and the
    /// checks off the pane, and those are what it is opened for. Closed it
    /// costs one row, and that row carries the first line so the fold is
    /// not a blind one.
    ///
    /// Keyed to the pull request, so moving to the next one starts closed
    /// again rather than inheriting the last one's fold.
    @ViewBuilder
    private func description(_ detail: PullRequestDetail) -> some View {
        if detail.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section {
                Text("This pull request was opened with a title only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                sectionTitle("Description")
            }
        } else {
            DescriptionSection(source: detail.body)
                .id(item.id)
        }
    }

    // MARK: - The files

    @ViewBuilder
    private var changedFiles: some View {
        switch files {
        case .loaded(let files) where !files.isEmpty:
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(files) { file in
                        fileRow(file)
                    }
                    // Against the count GitHub gave for the pull request,
                    // not against the page size: the rows can never exceed
                    // the page size, so comparing the two meant this never
                    // appeared and a long diff was cut without a word.
                    if unreadFiles(besides: files) > 0 {
                        Text("and \(unreadFiles(besides: files)) more not read")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            } header: {
                sectionTitle("Files") {
                    if let first = files.first {
                        Button { openDiff(first) } label: {
                            Label("Review", systemImage: "rectangle.split.2x1")
                                .font(.caption)
                        }
                        .buttonStyle(.accessoryBar)
                        .pointerStyle(.link)
                        .help("Open the diff, starting at the first file")
                    }
                }
            }
        case .loading:
            Section {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading the diff\u{2026}").foregroundStyle(.secondary)
                }
                .font(.caption)
            } header: {
                sectionTitle("Files")
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Ink.orange)
            } header: {
                sectionTitle("Files")
            }
        case .loaded, nil:
            EmptyView()
        }
    }

    /// A row that opens the diff, rather than one that unfolds it.
    ///
    /// A pull request can touch thirty files, and thirty patches unfolded
    /// into a column four inches wide is not something anyone reads. The
    /// row is the index; the overlay is the reading.
    ///
    /// A plain button rather than the accessory style the other controls
    /// here use: that style sets its label in by a few points of its own,
    /// which left this column's file names indented past every other row in
    /// the pane. The colour says it can be clicked instead.
    /// How many files the pull request touches that were not read.
    ///
    /// The total comes from the detail, which GitHub counts itself; the rows
    /// come from a paged REST call that stops at a few hundred.
    private func unreadFiles(besides read: [ChangedFile]) -> Int {
        guard case .loaded(let detail) = detail else { return 0 }
        return max(0, detail.changedFiles - read.count)
    }

    private func fileRow(_ file: ChangedFile) -> some View {
        FileRow(file: file, open: { openDiff(file) })
    }

    /// Both numbers spelled out, since the row has room for one.
    private func discussion(_ detail: PullRequestDetail) -> String {
        let onDiff = detail.reviewConversations == 1
            ? "1 conversation on the diff"
            : "\(detail.reviewConversations) conversations on the diff"
        let inThread = detail.totalComments == 1
            ? "1 comment in the conversation"
            : "\(detail.totalComments) comments in the conversation"
        return "\(onDiff), \(inThread)"
    }

    private func statistic(_ value: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value)
                .font(.title3.monospacedDigit())
                .foregroundStyle(tint)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func checks(_ detail: PullRequestDetail) -> some View {
        Section {
            if detail.checks.isEmpty {
                Text("No checks ran on this pull request.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(detail.checks) { check in
                        HStack(spacing: 7) {
                            Image(systemName: check.status.symbolName)
                                // A step above the row text: the result is
                                // what is being scanned for, the name only
                                // says which check produced it.
                                .font(.body)
                                .foregroundStyle(tint(for: check.status))
                            Text(check.name)
                                .lineLimit(1)
                                .help(check.name)
                            Spacer(minLength: 0)
                        }
                        .font(.callout)
                    }
                }
            }
        } header: {
            // The summary is the point: 3 of 24 failing is the number that
            // decides whether this pull request is worth reviewing now.
            sectionTitle(
                "Checks",
                trailing: detail.checks.isEmpty
                    ? nil
                    : summary(of: detail)
            )
        }
    }

    private func summary(of detail: PullRequestDetail) -> String {
        var parts: [String] = []
        if !detail.failingChecks.isEmpty { parts.append("\(detail.failingChecks.count) failing") }
        if !detail.runningChecks.isEmpty { parts.append("\(detail.runningChecks.count) running") }
        parts.append("\(detail.passingChecks.count)/\(detail.checks.count) passing")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func reviewers(_ detail: PullRequestDetail) -> some View {
        Section {
            if detail.reviewers.isEmpty {
                Text("Nobody has been asked to review yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(detail.reviewers) { reviewer in
                        HStack(spacing: 7) {
                            if reviewer.isTeam {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                            } else {
                                AvatarView(url: reviewer.avatarURL, size: 22)
                            }
                            Text(reviewer.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: reviewer.state.symbolName)
                                .font(.body)
                                .foregroundStyle(tint(for: reviewer.state))
                                .help(reviewer.state.label)
                        }
                        .font(.callout)
                    }
                }
            }
        } header: {
            sectionTitle("Reviewers")
        }
    }

    private func sectionTitle(_ title: String, trailing: String? = nil) -> some View {
        sectionTitle(title) {
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The same, with something to press at the end of it.
    private func sectionTitle(
        _ title: String, @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            trailing()
        }
        .padding(.bottom, 4)
    }

    // The colours for a check and for a review live beside the legend
    // that explains them, with every other colour a row is drawn in.
    // There used to be a second copy of the first one here, and it had
    // already drifted: this one stayed on the system's own green, which
    // is too light to read at this size.
    private func tint(for status: ChecksStatus) -> Color { status.tint }

    private func tint(for state: ReviewState) -> Color { state.tint }
}

/// View-local state without `@State`: its macro implementation ships only
/// with Xcode, and this project builds against the Command Line Tools.
@MainActor
final class Disclosure: ObservableObject {
    @Published var isExpanded: Bool

    init(isExpanded: Bool = false) {
        self.isExpanded = isExpanded
    }
}

struct DescriptionSection: View {
    nonisolated static let title = "Description"

    let source: String
    @StateObject private var disclosure = Disclosure()

    var body: some View {
        DisclosureGroup(isExpanded: $disclosure.isExpanded) {
            MarkdownText(source: source)
                .padding(.top, 8)
        } label: {
            // A button rather than the bare label: on macOS only the
            // triangle toggles a DisclosureGroup, which leaves the word
            // "Description" looking like a control that does nothing. The
            // triangle keeps working -- it is its own hit area, so this
            // cannot toggle twice.
            Button {
                disclosure.isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("Description")
                        .font(.subheadline.weight(.semibold))
                    if !disclosure.isExpanded, let first = Self.firstLine(of: source, besides: Self.title) {
                        Text(first)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The first line with something on it, as a hint of what is folded
    /// away. Leading heading marks and quote marks are dropped: they are
    /// punctuation for a renderer, not words for a reader.
    ///
    /// A line that only repeats the section's own name is skipped: the
    /// house template opens with `## Description`, and "Description
    /// Description" is a row that says one thing twice.
    ///
    /// `nonisolated` because a `View` is on the main actor and this is a
    /// string function: without it a test calling it hops actors and traps.
    nonisolated static func firstLine(of source: String, besides title: String) -> String? {
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let stripped = line
                .drop { $0 == "#" || $0 == ">" || $0 == " " || $0 == "\t" }
                .trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { continue }
            if stripped.caseInsensitiveCompare(title) == .orderedSame { continue }
            return stripped
        }
        return nil
    }
}


/// One changed file in the detail pane, which opens the diff at it.
///
/// A chevron at the end of every row, a ground under the pointer, and the
/// pointer itself as a hand. The accent colour alone did not say it: the
/// pane is full of accent-coloured text that is not a target.
///
/// The chevron is the part that matters, because it is there before
/// anybody goes looking; the ground is for whoever is already on the row.
///
/// `@StateObject` rather than `@State`: this package builds without
/// Xcode, where the `State` macro is not available.
private struct FileRow: View {
    let file: ChangedFile
    let open: () -> Void

    @StateObject private var hover = ViewFlag()

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: file.change.symbolName)
                    .foregroundStyle(.secondary)

                Text(file.shortPath)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer(minLength: 4)

                if file.additions > 0 {
                    Text(verbatim: "+\(file.additions)")
                        .foregroundStyle(Ink.green)
                        .monospacedDigit()
                }
                if file.deletions > 0 {
                    Text(verbatim: "\u{2212}\(file.deletions)")
                        .foregroundStyle(Ink.red)
                        .monospacedDigit()
                }

                // The same mark a notification row uses for a row that
                // opens into something.
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .font(.caption)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                hover.isOn ? Color(nsColor: .quaternaryLabelColor).opacity(0.45) : .clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hover.isOn = $0 }
        .help("Open the diff at this file \u{2014} \(file.path)")
    }
}


/// A pull request's commits, read only once somebody opens them.
///
/// Shut when the pane opens, and that is the whole of what makes this
/// affordable: a pane is opened by arrowing down a list, and a request
/// per row of a list is a rate limit spent on nothing. The number is
/// already beside the other numbers, so the section says how many there
/// are before it has read a single one.
struct CommitsSection: View {
    let pullRequestID: String
    /// How many there are in all, which may be more than were fetched.
    let total: Int
    let pane: PaneWriting

    @StateObject private var disclosure = Disclosure()

    private var commits: CommitsState? { pane.state.pullRequestCommits[pullRequestID] }

    var body: some View {
        DisclosureGroup(isExpanded: $disclosure.isExpanded) {
            content.padding(.top, 6)
        } label: {
            // A button rather than the bare label, for the same reason
            // the description has one: on macOS only the triangle
            // toggles a DisclosureGroup.
            Button {
                disclosure.isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("Commits")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onChange(of: disclosure.isExpanded) {
            guard disclosure.isExpanded else { return }
            pane.controller.loadCommits(for: pullRequestID)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch commits {
        case .loading, nil:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the commits\u{2026}").foregroundStyle(.secondary)
            }
            .font(.caption)
        case .loaded(let commits):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                    if index > 0 { Divider() }
                    // Newest first, so the one at the top is the one the
                    // diff and the checks are about.
                    row(commit, isHead: index == 0)
                }
                if total > commits.count {
                    Text("\(total - commits.count) older ones, on GitHub")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Ink.orange)
                Button("Try again") { pane.controller.reloadCommits(for: pullRequestID) }
                    .controlSize(.small)
            }
            .font(.caption)
        }
    }

    private func row(_ commit: PullRequestCommit, isHead: Bool) -> some View {
        Button {
            guard let url = commit.url else { return }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(alignment: .top, spacing: 7) {
                AvatarView(url: commit.avatarURL, size: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text(commit.headline)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Color(nsColor: .labelColor))
                    HStack(spacing: 5) {
                        Text(verbatim: commit.abbreviated)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(Ink.blue)
                        if !commit.author.isEmpty {
                            Text(commit.author)
                        }
                        Text(RelativeTime.string(for: commit.committedAt))
                        if isHead {
                            Text(verbatim: "HEAD")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 3)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                // Its own checks, which is what makes this more than a
                // history: it says when the pull request went green.
                if commit.checks != .none {
                    Image(systemName: commit.checks.symbolName)
                        .font(.caption)
                        .foregroundStyle(commit.checks.tint)
                        .help(commit.checks.label)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Open this commit on GitHub")
    }
}
