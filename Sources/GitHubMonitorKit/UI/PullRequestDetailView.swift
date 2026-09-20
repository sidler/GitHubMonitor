import SwiftUI

/// The detail pane: what a reviewer wants to know before opening the browser.
struct PullRequestDetailView: View {
    let item: PullRequestItem
    let detail: DetailState?
    let reload: () -> Void
    let close: () -> Void

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
                        changes(detail)
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
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Sections

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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(detail.checks) { check in
                        HStack(spacing: 6) {
                            Image(systemName: check.status.symbolName)
                                .foregroundStyle(tint(for: check.status))
                            Text(check.name)
                                .lineLimit(1)
                                .help(check.name)
                            Spacer(minLength: 0)
                        }
                        .font(.caption)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(detail.reviewers) { reviewer in
                        HStack(spacing: 6) {
                            if reviewer.isTeam {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                            } else {
                                AvatarView(url: reviewer.avatarURL, size: 18)
                            }
                            Text(reviewer.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: reviewer.state.symbolName)
                                .foregroundStyle(tint(for: reviewer.state))
                                .help(reviewer.state.label)
                        }
                        .font(.caption)
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
