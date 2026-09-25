import SwiftUI

/// The detail pane: what a reviewer wants to know before opening the browser.
struct PullRequestDetailView: View {
    let item: PullRequestItem
    let detail: DetailState?
    /// Fetched separately from the rest, so it arrives on its own schedule.
    let files: ChangedFilesState?
    let reload: () -> Void
    let close: () -> Void

    @StateObject private var expansion = PatchExpansion()

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

    // MARK: - The files

    @ViewBuilder
    private var changedFiles: some View {
        switch files {
        case .loaded(let files) where !files.isEmpty:
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(files.prefix(ChangedFilesQuery.pageSize)) { file in
                        fileRow(file)
                    }
                    if files.count > ChangedFilesQuery.pageSize {
                        Text("and \(files.count - ChangedFilesQuery.pageSize) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    private func fileRow(_ file: ChangedFile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: file.change.symbolName)
                    .foregroundStyle(.secondary)
                    .help(file.change.label)

                Button {
                    if let url = file.url(pullRequest: item.url) { NSWorkspace.shared.open(url) }
                } label: {
                    Text(file.shortPath)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .buttonStyle(.link)
                .help(file.path)

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

                // Only where there is something to unfold. A file with no
                // patch is binary or was too large for GitHub to send.
                if file.patch != nil, !file.isSmall {
                    Button {
                        expansion.toggle(file.path)
                    } label: {
                        Image(systemName: expansion.isOpen(file.path) ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                    }
                    .buttonStyle(.accessoryBar)
                    .help(expansion.isOpen(file.path) ? "Hide the diff" : "Show the diff")
                }
            }
            .font(.caption)

            // A small change is shown without being asked for: most pull
            // requests here are one file and a few lines, and a row to click
            // would be a step between someone and what they opened this for.
            if let patch = file.patch, file.isSmall || expansion.isOpen(file.path) {
                PatchView(patch: patch, language: file.language)
            }
        }
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
