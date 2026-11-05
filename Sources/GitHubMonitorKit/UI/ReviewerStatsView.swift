import SwiftUI

/// Who does the reviewing in a repository, and how long the rest of the
/// team waits on them.
///
/// Two tables rather than one. How much somebody reviews and how fast
/// they answer are different questions, and a single table ranked by one
/// of them invites the other to be read off the same order -- which is
/// exactly the reading the numbers do not support.
struct ReviewerStatsView: View {
    @Bindable var state: AppState
    let controller: RefreshController
    /// Whether this is the ranking by volume or the one by speed.
    let bySpeed: Bool

    var body: some View {
        switch state.reviewerStats {
        case .unconfigured:
            ContentUnavailableView(
                "No repository chosen",
                systemImage: "person.2",
                description: Text("Pick a repository above to see who reviews its pull requests.")
            )
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading the reviews\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not read the reviews", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await controller.loadReviewerStats(force: true) } }
            }
        case .loaded(let data):
            table(data)
        }
    }

    private var rows: [ReviewerStats] {
        guard let data = state.reviewerStats.data else { return [] }
        return bySpeed
            ? ReviewerStatsMath.bySpeed(data.stats)
            : ReviewerStatsMath.byVolume(data.stats)
    }

    @ViewBuilder
    private func table(_ data: ReviewerStatsData) -> some View {
        if rows.isEmpty {
            ContentUnavailableView(
                bySpeed ? "Nothing to measure" : "No reviews",
                systemImage: "person.2",
                description: Text(
                    bySpeed
                        ? "Nobody in \(data.repository) answered a review request in this period."
                        : "Nobody reviewed a pull request in \(data.repository) in this period."
                )
            )
        } else {
            VStack(spacing: 0) {
                if let reason = data.truncationReason {
                    notice(reason)
                }
                if !bySpeed {
                    // Two bare numbers at the end of a row are two numbers
                    // with no name. The speed table needs none: it labels
                    // its figures between them, where the eye already is.
                    volumeHeader
                    Divider()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { place, row in
                            if bySpeed {
                                SpeedRow(stats: row, longest: longest)
                            } else {
                                VolumeRow(place: place + 1, stats: row, most: most)
                            }
                            Divider()
                        }
                    }
                    .padding(.vertical, 4)
                }
                Divider()
                footer(data)
            }
        }
    }

    private var volumeHeader: some View {
        HStack(spacing: 10) {
            Text("#")
                .frame(width: 24, alignment: .trailing)
            Text("reviewer")
                .frame(width: 180, alignment: .leading)
            Spacer(minLength: 0)
            Text("PRs")
                .frame(width: 60, alignment: .trailing)
            Text("reviews")
                .frame(width: 60, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    /// What the bars are measured against, so every row is drawn to the
    /// same scale.
    private var longest: TimeInterval {
        rows.compactMap(\.median).max() ?? 1
    }

    private var most: Int {
        rows.map(\.pullRequests).max() ?? 1
    }

    private func notice(_ reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(reason)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(Ink.orange)
        .padding(.vertical, 5)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.orange.opacity(0.1))
    }

    /// What the columns mean, in the same place the numbers end.
    ///
    /// Every one of these could be counted half a dozen ways, and a
    /// ranking of colleagues is the last place to leave that to the
    /// reader's assumption.
    private func footer(_ data: ReviewerStatsData) -> some View {
        HStack(spacing: 6) {
            Text(
                bySpeed
                    ? "From being asked to answering, wall-clock \u{00B7} n = answered requests"
                        + " \u{00B7} ignored = still asked when the pull request closed"
                        + " \u{00B7} pending = still asked, still open"
                    : "PRs = pull requests reviewed at least once"
                        + " \u{00B7} reviews = every review submitted, comment rounds included"
            )
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("\(data.pullRequests) pull requests since \(RelativeTime.absolute(data.since))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

/// One line of the ranking by how much somebody reviews.
private struct VolumeRow: View {
    let place: Int
    let stats: ReviewerStats
    let most: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("\(place)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 24, alignment: .trailing)

            Text(stats.reviewer)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            // The bar is the pull requests, not the reviews: the number
            // of people's work somebody has read is the one that says how
            // much of the reviewing they carry.
            GeometryReader { proxy in
                Capsule()
                    .fill(Ink.blue.opacity(0.7))
                    .frame(
                        width: max(2, proxy.size.width * share),
                        height: 10
                    )
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)

            Text("\(stats.pullRequests)")
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
            Text("\(stats.reviews)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .help("\(stats.reviewer): \(stats.reviews) reviews across \(stats.pullRequests) pull requests")
    }

    private var share: Double {
        guard most > 0 else { return 0 }
        return Double(stats.pullRequests) / Double(most)
    }
}

/// One line of the ranking by how long people wait.
private struct SpeedRow: View {
    let stats: ReviewerStats
    let longest: TimeInterval

    var body: some View {
        HStack(spacing: 10) {
            Text(stats.reviewer)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            GeometryReader { proxy in
                Capsule()
                    .fill(tint.opacity(0.7))
                    .frame(width: max(2, proxy.size.width * share), height: 10)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)

            number(stats.median.map(TrendMath.describe) ?? "\u{2014}", width: 66, bold: true)
            label("mean")
            number(stats.mean.map(TrendMath.describe) ?? "\u{2014}", width: 60)
            label("p90")
            number(stats.p90.map(TrendMath.describe) ?? "\u{2014}", width: 60)
            number("n=\(stats.answered)", width: 56)
            number(ignored, width: 118)
            number("pending \(stats.pending)", width: 86)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .help(help)
    }

    private var share: Double {
        guard longest > 0, let median = stats.median else { return 0 }
        return median / longest
    }

    /// Red only where somebody is being asked and not answering. Slow is
    /// not the same failing as absent, and the colour should not say it
    /// is.
    private var tint: Color {
        guard let share = stats.ignoredShare else { return Ink.blue }
        if share >= 0.25 { return Ink.red }
        if share >= 0.1 { return Ink.orange }
        return Ink.blue
    }

    private var ignored: String {
        guard let share = stats.ignoredShare, stats.ignored > 0 else { return "" }
        return "ignored \(Int((share * 100).rounded()))% (\(stats.ignored))"
    }

    private var help: String {
        "\(stats.reviewer): \(stats.answered) requests answered"
            + ", \(stats.ignored) left unanswered when the pull request closed"
            + ", \(stats.pending) still waiting"
    }

    private func number(_ text: String, width: CGFloat, bold: Bool = false) -> some View {
        Text(text)
            .font(.callout.monospacedDigit().weight(bold ? .medium : .regular))
            .foregroundStyle(bold ? Color(nsColor: .labelColor) : .secondary)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
