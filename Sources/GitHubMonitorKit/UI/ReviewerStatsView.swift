import Charts
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

    @StateObject private var hover = ReviewerHover()

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
                chart
                Divider()
                footer(data)
            }
        }
    }

    /// Drawn the way the two charts beside it are: a row per person, the
    /// name down the side, gridlines across, and a legend at the top
    /// saying what the segments are. A fourth view in the same place that
    /// drew its bars differently would read as a different app.
    private var chart: some View {
        Chart(rows) { row in
            if bySpeed {
                BarMark(
                    x: .value("Time to review", row.median ?? 0),
                    y: .value("Reviewer", row.reviewer)
                )
                .foregroundStyle(by: .value("Kind", band(row)))
            } else {
                BarMark(
                    x: .value("Pull requests", row.pullRequests),
                    y: .value("Reviewer", row.reviewer)
                )
                .foregroundStyle(by: .value("Kind", Segment.read))

                // The rounds beyond the first, so the bar is every review
                // submitted and the split says how much of it was going
                // back over the same pull request.
                BarMark(
                    x: .value("Pull requests", max(0, row.reviews - row.pullRequests)),
                    y: .value("Reviewer", row.reviewer)
                )
                .foregroundStyle(by: .value("Kind", Segment.again))
            }
        }
        .chartForegroundStyleScale(scale)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6, roundLowerBound: true)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if bySpeed, let seconds = value.as(Double.self) {
                        Text(TrendMath.describe(seconds))
                    } else if let count = value.as(Int.self) {
                        Text(verbatim: "\(count)")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading)
        }
        .chartLegend(position: .top, alignment: .leading)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plot = proxy.plotFrame else { return }
                            hover.name = proxy.value(
                                atY: location.y - geometry[plot].origin.y, as: String.self
                            )
                        case .ended:
                            hover.name = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let row = rows.first(where: { $0.reviewer == hover.name }) {
                ChartTooltip(title: row.reviewer, lines: lines(for: row))
            }
        }
        .frame(minHeight: CGFloat(rows.count) * 28 + 80)
        .padding(16)
        .scrollableIfTall(rowCount: rows.count)
    }

    /// The segments, named for what they are rather than for the column
    /// they came from.
    private enum Segment: String, Plottable {
        case read = "Pull requests read"
        case again = "Further rounds"
        case prompt = "Answers"
        case slow = "Some requests ignored"
        case absent = "Many requests ignored"
    }

    /// Red only where somebody is being asked and not answering. Slow is
    /// not the same failing as absent, and the colour should not say it
    /// is.
    private func band(_ row: ReviewerStats) -> Segment {
        guard let share = row.ignoredShare else { return .prompt }
        if share >= 0.25 { return .absent }
        if share >= 0.1 { return .slow }
        return .prompt
    }

    private var scale: KeyValuePairs<Segment, Color> {
        bySpeed
            ? [
                Segment.prompt: Color.accentColor,
                Segment.slow: Color.orange,
                Segment.absent: Color.red,
            ]
            : [
                Segment.read: Color.accentColor,
                Segment.again: Color.secondary.opacity(0.45),
            ]
    }

    /// Everything the table used to print in columns. In the tooltip
    /// because that is where the other two views put their detail, and
    /// because a chart with six numbers beside every bar is a table
    /// pretending to be a chart.
    private func lines(for row: ReviewerStats) -> [String] {
        guard bySpeed else {
            return [
                "\(row.pullRequests) pull requests read",
                "\(row.reviews) reviews submitted",
            ]
        }
        var lines = [
            "median \(row.median.map(TrendMath.describe) ?? "\u{2014}")",
            "mean \(row.mean.map(TrendMath.describe) ?? "\u{2014}")"
                + " \u{00B7} p90 \(row.p90.map(TrendMath.describe) ?? "\u{2014}")",
            "\(row.answered) requests answered",
        ]
        if row.ignored > 0, let share = row.ignoredShare {
            lines.append("\(row.ignored) ignored (\(Int((share * 100).rounded()))%)")
        }
        if row.pending > 0 { lines.append("\(row.pending) still waiting") }
        return lines
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
                    ? "From being asked to answering, wall-clock"
                        + " \u{00B7} ignored = still asked when the pull request closed"
                        + " \u{00B7} hover a bar for the rest"
                    : "Pull requests read, each counted once"
                        + " \u{00B7} further rounds = reviews beyond the first on the same one"
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

/// The row the pointer is over.
@MainActor
final class ReviewerHover: ObservableObject {
    @Published var name: String?
}
