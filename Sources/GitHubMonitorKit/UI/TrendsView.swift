import Charts
import Combine
import SwiftUI

@MainActor
private final class TrendHoverModel: ObservableObject {
    /// The period the pointer is over, per chart.
    @Published var hovered: [TrendMetric: Date] = [:]
}

/// How a repository's pull requests have moved over time: how long they wait
/// for a review, for an approval, for a merge, and how many there are.
///
/// Separate from the workload dashboard on purpose. That one answers "who is
/// carrying what right now"; this one answers "is it getting better or
/// worse", which needs a different fetch, a different cache and a different
/// shape of chart.
struct TrendsView: View {
    @Bindable var state: AppState
    let controller: RefreshController

    @StateObject private var hover = TrendHoverModel()

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            switch state.trends {
            case .unconfigured:
                ContentUnavailableView(
                    "No repository chosen",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Pick a repository in Workload to see how its pull requests move over time.")
                )
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load the history", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { load(force: true) }
                }
            case .loading(nil):
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the history…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading(.some(let data)), .loaded(let data):
                charts(data)
            }
        }
        // Keyed on the token too: opening this before the keychain read has
        // finished would otherwise leave it empty until the next click.
        .task(id: reloadKey) { load() }
    }

    private var reloadKey: String {
        "\(state.settings.dashboardRepository)|\(state.settings.trendResolution.rawValue)|\(state.hasToken)"
    }

    private func load(force: Bool = false) {
        Task { await controller.loadTrends(force: force) }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            // The repository is the workload view's setting: both answer
            // questions about the same repository, and two fields would be
            // two places to have it wrong.
            Text(state.settings.dashboardRepository.isEmpty
                ? "No repository"
                : state.settings.dashboardRepository)
                .font(.headline)

            TrendControls(settings: state.settings)

            Spacer()

            if let data = state.trends.data {
                if state.trends.isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(data.buckets.count) of \(data.resolution.bucketCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Read \(RelativeTime.string(for: data.fetchedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(RelativeTime.absolute(data.fetchedAt))
                }

                Button {
                    load(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.accessoryBar)
                .disabled(state.trends.isLoading)
                .help("Read the history again")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Charts

    private func charts(_ data: TrendData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let reason = data.truncationReason {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                ForEach(TrendMetric.allCases, id: \.self) { metric in
                    chart(metric, data: data)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func chart(_ metric: TrendMetric, data: TrendData) -> some View {
        let points = self.points(metric, data: data)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.title)
                    .font(.headline)
                Text(metric.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if points.allSatisfy({ $0.value == nil }) {
                Text("Nothing to show for these periods.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                body(for: metric, points: points, data: data)
            }
        }
    }

    private func body(for metric: TrendMetric, points: [TrendSample], data: TrendData) -> some View {
        let unit = metric.isDuration
            ? TrendMath.unit(for: points.compactMap(\.value))
            : nil

        return Chart {
            ForEach(points) { point in
                if let value = point.value {
                    // A gap in the data stays a gap: joining across a period
                    // with no pull requests would draw a number nobody
                    // measured.
                    LineMark(
                        x: .value("Period", point.start),
                        y: .value(metric.title, scaled(value, unit: unit)),
                        series: .value("Series", point.series)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Period", point.start),
                        y: .value(metric.title, scaled(value, unit: unit))
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .symbolSize(hover.hovered[metric] == point.start ? 90 : 40)
                }
            }
        }
        .chartLegend(metric == .volume ? .visible : .hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(date, resolution: data.resolution))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(verbatim: axisNumber(number, unit: unit))
                    }
                }
            }
        }
        .chartYAxisLabel(unit?.axisLabel ?? "pull requests")
        .frame(height: 150)
        .chartOverlay { proxy in hoverCatcher(metric, proxy: proxy, points: points) }
        .overlay(alignment: .topTrailing) {
            if let start = hover.hovered[metric] {
                tooltip(metric: metric, start: start, points: points, unit: unit, data: data)
            }
        }
    }

    // MARK: - Points

    /// One drawn point: a period, a value and which line it belongs to.
    struct TrendSample: Identifiable {
        var id: String { "\(series)-\(start.timeIntervalSince1970)" }
        let start: Date
        let value: Double?
        let samples: Int
        let series: String
    }

    private func points(_ metric: TrendMetric, data: TrendData) -> [TrendSample] {
        let includeBots = state.settings.trendsIncludeBots

        if metric == .volume {
            return data.buckets.flatMap { bucket -> [TrendSample] in
                let values = bucket.values(includingBots: includeBots)
                return [
                    TrendSample(
                        start: bucket.start,
                        value: Double(values.opened),
                        samples: values.opened,
                        series: "Opened"
                    ),
                    TrendSample(
                        start: bucket.start,
                        value: Double(values.merged),
                        samples: values.merged,
                        series: "Merged"
                    ),
                ]
            }
        }

        return data.buckets.map { bucket in
            let point = bucket.values(includingBots: includeBots).point(for: metric)
            return TrendSample(
                start: bucket.start,
                value: point.median,
                samples: point.samples,
                series: metric.title
            )
        }
    }

    private func scaled(_ value: Double, unit: TrendMath.DurationUnit?) -> Double {
        guard let unit else { return value }
        return value / unit.seconds
    }

    private func axisNumber(_ value: Double, unit: TrendMath.DurationUnit?) -> String {
        guard unit != nil else { return "\(Int(value.rounded()))" }
        return value < 10 ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
    }

    private func axisLabel(_ date: Date, resolution: TrendResolution) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = resolution == .weekly ? "d MMM" : "MMM yy"
        return formatter.string(from: date)
    }

    // MARK: - Hover

    private func hoverCatcher(
        _ metric: TrendMetric,
        proxy: ChartProxy,
        points: [TrendSample]
    ) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let plot = proxy.plotFrame else {
                            hover.hovered[metric] = nil
                            return
                        }
                        let x = location.x - geometry[plot].origin.x
                        guard let date: Date = proxy.value(atX: x) else {
                            hover.hovered[metric] = nil
                            return
                        }
                        // The nearest period, so the tooltip follows the
                        // pointer instead of only appearing dead on a point.
                        hover.hovered[metric] = points
                            .map(\.start)
                            .min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
                    case .ended:
                        hover.hovered[metric] = nil
                    }
                }
        }
    }

    private func tooltip(
        metric: TrendMetric,
        start: Date,
        points: [TrendSample],
        unit: TrendMath.DurationUnit?,
        data: TrendData
    ) -> some View {
        let here = points.filter { $0.start == start }

        return VStack(alignment: .leading, spacing: 2) {
            Text(periodLabel(start, resolution: data.resolution))
                .font(.caption.weight(.semibold))

            ForEach(here) { point in
                if let value = point.value {
                    Text(verbatim: metric.isDuration
                        ? "\(point.series): \(TrendMath.describe(value))"
                        : "\(point.series): \(Int(value))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(point.series): no data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if metric.isDuration, let samples = here.first?.samples {
                // The median of two says something very different from the
                // median of forty, and the line cannot show that.
                Text(verbatim: "n = \(samples)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary, lineWidth: 1))
        .padding(8)
        .allowsHitTesting(false)
    }

    private func periodLabel(_ start: Date, resolution: TrendResolution) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        switch resolution {
        case .weekly:
            formatter.dateFormat = "'Week of' d MMM yyyy"
        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
        }
        return formatter.string(from: start)
    }
}


/// The resolution switch and the bot toggle.
///
/// Their own view because `settings` is a let on the state, and a binding
/// needs the object itself.
private struct TrendControls: View {
    @Bindable var settings: Settings

    var body: some View {
        HStack(spacing: 10) {
            Picker("", selection: $settings.trendResolution) {
                ForEach(TrendResolution.allCases, id: \.self) { resolution in
                    Text(resolution.label).tag(resolution)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Toggle("Include bots", isOn: $settings.trendsIncludeBots)
                .toggleStyle(.checkbox)
                .help("Pull requests opened by renovate and its kind. Reviews by bots never count.")
        }
    }
}
