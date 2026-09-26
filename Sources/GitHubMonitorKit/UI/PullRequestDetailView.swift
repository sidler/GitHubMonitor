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
                        changedFiles
                        checks(detail)
                        reviewers(detail)
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
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
                statistic("+\(detail.additions)", caption: "added", tint: .green)
                statistic("−\(detail.deletions)", caption: "removed", tint: .red)
                statistic(
                    "\(detail.comments)",
                    caption: detail.comments == 1 ? "comment" : "comments",
                    tint: .primary
                )
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
                sectionTitle("Files")
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
                    .foregroundStyle(.orange)
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
        Button {
            openDiff(file)
        } label: {
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
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }
                if file.deletions > 0 {
                    Text(verbatim: "\u{2212}\(file.deletions)")
                        .foregroundStyle(.red)
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(file.change.label) \u{2014} \(file.path)")
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
        .padding(.bottom, 4)
    }

    private func tint(for status: ChecksStatus) -> Color {
        switch status {
        case .success: .green
        case .failure: .red
        case .pending: .yellow
        case .none: .secondary
        }
    }

    private func tint(for state: ReviewState) -> Color {
        switch state {
        case .approved: .green
        case .changesRequested: .orange
        case .commented: .secondary
        case .dismissed: .secondary
        case .pending: .yellow
        }
    }
}

/// View-local state without `@State`: its macro implementation ships only
/// with Xcode, and this project builds against the Command Line Tools.
@MainActor
private final class Disclosure: ObservableObject {
    @Published var isExpanded = false
}

struct DescriptionSection: View {
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
                    if !disclosure.isExpanded, let first = Self.firstLine(of: source) {
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
    /// `nonisolated` because a `View` is on the main actor and this is a
    /// string function: without it a test calling it hops actors and traps.
    nonisolated static func firstLine(of source: String) -> String? {
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let stripped = line
                .drop { $0 == "#" || $0 == ">" || $0 == " " || $0 == "\t" }
                .trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { return stripped }
        }
        return nil
    }
}
