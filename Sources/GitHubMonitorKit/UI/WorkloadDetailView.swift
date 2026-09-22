import SwiftUI

/// The detail pane for a bar in the workload chart: which pull requests the
/// number is made of.
///
/// A bar says how much somebody is carrying; this says what. Without it the
/// chart can only ever start a conversation -- the next question is always
/// "which ones?", and answering it meant going to GitHub and rebuilding the
/// same filter by hand.
struct WorkloadDetailView: View {
    let detail: WorkloadDetail
    /// The repository the chart is about, for the line under the name.
    let repository: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if detail.pullRequests.isEmpty {
                        Text("Nothing open here any more.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        section("Ready for review", items: detail.ready)
                        section("Drafts", items: detail.drafts)
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
                HStack(spacing: 7) {
                    if detail.isTeam {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                    } else {
                        AvatarView(url: detail.avatarURL, size: 22)
                    }
                    Text(detail.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.accessoryBar)
                .help("Close details")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.subtitle)
                if !repository.isEmpty {
                    Text(repository)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var footer: some View {
        BottomBar {
            HStack {
                Text(count)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                // A row opens one pull request; this opens the same question
                // on GitHub, where it can be filtered further.
                if let url = searchURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open on GitHub", systemImage: "arrow.up.forward.square")
                    }
                    .buttonStyle(.accessoryBar)
                }
            }
        }
    }

    private var count: String {
        let total = detail.pullRequests.count
        let drafts = detail.drafts.count
        let base = total == 1 ? "1 pull request" : "\(total) pull requests"
        return drafts == 0 ? base : "\(base) · \(drafts) draft\(drafts == 1 ? "" : "s")"
    }

    /// The same list on GitHub: the repository, open, and whoever the bar is
    /// about -- as its author or as the reviewer being waited on.
    private var searchURL: URL? {
        guard !repository.isEmpty, !detail.isTeam else { return nil }
        let qualifier = detail.subtitle.hasPrefix("Open")
            ? "author:\(detail.title)"
            : "review-requested:\(detail.title)"
        var components = URLComponents(string: "https://github.com/\(repository)/pulls")
        components?.queryItems = [URLQueryItem(name: "q", value: "is:pr is:open \(qualifier)")]
        return components?.url
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(_ title: String, items: [PullRequestItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: "\(items.count)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }

                ForEach(items) { item in
                    // No inspect action: the pane is already the detail, so a
                    // row's job here is to open the pull request itself.
                    PullRequestRow(item: item, compact: true)
                }
            }
        }
    }
}
