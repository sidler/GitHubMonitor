import Charts
import Combine
import SwiftUI

@MainActor
private final class MyTrendHoverModel: ObservableObject {
    @Published var hovered: [MyTrendMetric: Date] = [:]
}

/// The same questions as the repository trends, asked about one's own pull
/// requests: how many, at what hour, how much was said on them, by whom, and
/// how long they took to land.
///
/// Scoped to the signed-in user and to the repository filters the lists work
/// under, so it describes the same body of work the rest of the app shows.
struct MyTrendsView: View {
    @Bindable var state: AppState
    let controller: RefreshController

    @StateObject private var hover = MyTrendHoverModel()

    private static let topCommenters = 10

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            switch state.myTrends {
            case .unconfigured:
                ContentUnavailableView(
                    "No account yet",
                    systemImage: "person.crop.circle.badge.clock",
                    description: Text("Add a token in Settings to see your own pull requests over time.")
                )
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load your history", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { load(force: true) }
                }
            case .loading(nil):
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Reading your history…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading(.some(let data)), .loaded(let data):
                charts(data)
            }
        }
        .task(id: reloadKey) { load() }
    }

    private var reloadKey: String {
        "\(state.viewer?.login ?? "")|\(state.settings.trendResolution.rawValue)|\(state.hasToken)"
    }

    private func load(force: Bool = false) {
        Task { await controller.loadMyTrends(force: force) }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Text(state.viewer.map { "@\($0.login)" } ?? "Your pull requests")
                .font(.headline)

            TrendResolutionPicker(settings: state.settings)

            Toggle("Include bots", isOn: botBinding)
                .toggleStyle(.checkbox)
                .help("Comments written by bots — CI, coverage reports and their kind.")

            Spacer()

            if let data = state.myTrends.data {
                if state.myTrends.isLoading {
                    ProgressView().controlSize(.small)
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
                .disabled(state.myTrends.isLoading)
                .help("Read your history again")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var botBinding: Binding<Bool> {
        Binding(
            get: { state.settings.trendsIncludeBots },
            set: { state.settings.trendsIncludeBots = $0 }
        )
    }

    // MARK: - Charts

    private func charts(_ data: MyTrendData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let reason = data.truncationReason {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                ForEach(MyTrendMetric.allCases, id: \.self) { metric in
                    section(metric, data: data)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section(_ metric: MyTrendMetric, data: MyTrendData) -> some View {
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

            switch metric {
            case .opened: openedChart(data)
            case .hourOfDay: hourChart(data)
            case .comments: commentsChart(data)
            case .commenters: commenterChart(data)
            case .merge: mergeChart(data)
            }
        }
    }

    /// How many you opened per period.
    private func openedChart(_ data: MyTrendData) -> some View {
        timeChart(
            metric: .opened,
            data: data,
            series: [("Opened", Color.accentColor)],
            value: { bucket, _ in Double(bucket.opened) },
            unit: nil,
            axisTitle: "pull requests"
        )
    }

    /// Fewest, middle and most comments on one pull request.
    private func commentsChart(_ data: MyTrendData) -> some View {
        let includeBots = state.settings.trendsIncludeBots
        return timeChart(
            metric: .comments,
            data: data,
            series: [
                (TrendLine.median.label, .accentColor),
                (TrendLine.fastest.label, .green),
                (TrendLine.slowest.label, .orange),
            ],
            value: { bucket, series in
                let point = bucket.comments(includingBots: includeBots)
                return switch series {
                case TrendLine.fastest.label: point.fastest
                case TrendLine.slowest.label: point.slowest
                default: point.median
                }
            },
            unit: nil,
            axisTitle: "comments",
            // "Fastest" and "slowest" are the wrong words for a count.
            legendNames: [
                TrendLine.median.label: "Median",
                TrendLine.fastest.label: "Fewest",
                TrendLine.slowest.label: "Most",
            ]
        )
    }

    private func mergeChart(_ data: MyTrendData) -> some View {
        let values = data.buckets.flatMap { [$0.merge.median].compactMap { $0 } }
        let unit = TrendMath.unit(for: values)
        return timeChart(
            metric: .merge,
            data: data,
            series: [
                (TrendLine.median.label, .accentColor),
                (TrendLine.fastest.label, .green),
                (TrendLine.slowest.label, .orange),
            ],
            value: { bucket, series in
                switch series {
                case TrendLine.fastest.label: bucket.merge.fastest
                case TrendLine.slowest.label: bucket.merge.slowest
                default: bucket.merge.median
                }
            },
            unit: unit,
            axisTitle: unit.axisLabel
        )
    }

    /// One line per series, over the periods.
    private func timeChart(
        metric: MyTrendMetric,
        data: MyTrendData,
        series: [(name: String, colour: Color)],
        value: @escaping (MyTrendBucket, String) -> Double?,
        unit: TrendMath.DurationUnit?,
        axisTitle: String,
        legendNames: [String: String] = [:]
    ) -> some View {
        let samples = data.buckets.flatMap { bucket in
            series.compactMap { entry -> (start: Date, value: Double, series: String)? in
                guard let raw = value(bucket, entry.name) else { return nil }
                return (bucket.start, unit.map { raw / $0.seconds } ?? raw, legendNames[entry.name] ?? entry.name)
            }
        }
        let names = series.map { legendNames[$0.name] ?? $0.name }

        return Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                LineMark(
                    x: .value("Period", sample.start),
                    y: .value(metric.title, sample.value),
                    series: .value("Series", sample.series)
                )
                .foregroundStyle(by: .value("Series", sample.series))
                .interpolationMethod(.monotone)

                if sample.series == names.first {
                    PointMark(
                        x: .value("Period", sample.start),
                        y: .value(metric.title, sample.value)
                    )
                    .foregroundStyle(by: .value("Series", sample.series))
                    .symbolSize(hover.hovered[metric] == sample.start ? 90 : 40)
                }
            }
        }
        .chartForegroundStyleScale(domain: names, range: series.map(\.colour))
        .chartLegend(series.count > 1 ? .visible : .hidden)
        // Logarithmic wherever both ends are drawn: the slowest is routinely
        // a hundred times the middle, and on a linear axis it presses the
        // other lines flat against the bottom.
        .chartYScale(type: series.count > 1 ? .symmetricLog : .linear)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(TrendAxis.periodTick(date, resolution: data.resolution))
                    }
                }
            }
        }
        .chartYAxis {
            // Decades where the axis is logarithmic, the chart's own choice
            // where it is not: an empty list of values would leave a chart
            // with no ticks at all.
            let decades = TrendAxis.decades(samples.map(\.value), enabled: series.count > 1)
            if decades.isEmpty {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(verbatim: TrendAxis.number(number))
                        }
                    }
                }
            } else {
                AxisMarks(values: decades) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(verbatim: TrendAxis.number(number))
                        }
                    }
                }
            }
        }
        .chartYAxisLabel(axisTitle)
        .frame(height: 150)
        .chartOverlay { proxy in hoverCatcher(metric, proxy: proxy, starts: data.buckets.map(\.start)) }
        .overlay(alignment: .topTrailing) {
            if let start = hover.hovered[metric] {
                tooltip(metric: metric, start: start, data: data, unit: unit)
            }
        }
    }

    /// The hour of the day each pull request was opened.
    ///
    /// Bars over the clock rather than a line over time: this one is not a
    /// trend but a shape, and it needs the whole range to have one at all.
    private func hourChart(_ data: MyTrendData) -> some View {
        let hours = data.hours
        return Chart(0..<24, id: \.self) { hour in
            BarMark(
                x: .value("Hour", hour),
                y: .value("Pull requests", hours[hour] ?? 0)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXScale(domain: -1...24)
        .chartXAxis {
            AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(verbatim: String(format: "%02d:00", hour))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let count = value.as(Int.self) {
                        Text(verbatim: "\(count)")
                    }
                }
            }
        }
        .chartYAxisLabel("pull requests")
        .frame(height: 140)
    }

    /// Who wrote on your pull requests, most first.
    private func commenterChart(_ data: MyTrendData) -> some View {
        let people = Array(
            data.commenters(includingBots: state.settings.trendsIncludeBots)
                .prefix(Self.topCommenters)
        )

        return Group {
            if people.isEmpty {
                Text("Nobody commented in this range.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                Chart(people, id: \.login) { person in
                    BarMark(
                        x: .value("Comments", person.comments),
                        y: .value("Who", person.login)
                    )
                    .foregroundStyle(Color.accentColor)
                    .annotation(position: .trailing) {
                        Text(verbatim: "\(person.comments)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text(verbatim: "\(count)")
                            }
                        }
                    }
                }
                .chartYAxis { AxisMarks(preset: .aligned, position: .leading) }
                .frame(height: CGFloat(people.count) * 24 + 30)
            }
        }
    }

    // MARK: - Hover

    private func hoverCatcher(
        _ metric: MyTrendMetric,
        proxy: ChartProxy,
        starts: [Date]
    ) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard
                            let plot = proxy.plotFrame,
                            let date: Date = proxy.value(atX: location.x - geometry[plot].origin.x)
                        else {
                            hover.hovered[metric] = nil
                            return
                        }
                        hover.hovered[metric] = starts
                            .min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
                    case .ended:
                        hover.hovered[metric] = nil
                    }
                }
        }
    }

    @ViewBuilder
    private func tooltip(
        metric: MyTrendMetric,
        start: Date,
        data: MyTrendData,
        unit: TrendMath.DurationUnit?
    ) -> some View {
        if let bucket = data.buckets.first(where: { $0.start == start }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(TrendAxis.periodName(start, resolution: data.resolution))
                    .font(.caption.weight(.semibold))

                switch metric {
                case .opened:
                    line("Opened", "\(bucket.opened)")
                case .comments:
                    let point = bucket.comments(includingBots: state.settings.trendsIncludeBots)
                    line("Fewest", point.fastest.map { "\(Int($0))" })
                    line("Median", point.median.map { "\(Int($0))" })
                    line("Most", point.slowest.map { "\(Int($0))" })
                    samples(point.samples, noun: "pull requests")
                case .merge:
                    line("Fastest", bucket.merge.fastest.map(TrendMath.describe))
                    line("Median", bucket.merge.median.map(TrendMath.describe))
                    line("Slowest", bucket.merge.slowest.map(TrendMath.describe))
                    samples(bucket.merge.samples, noun: "merged")
                case .hourOfDay, .commenters:
                    EmptyView()
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary, lineWidth: 1))
            .padding(8)
            .allowsHitTesting(false)
        }
    }

    private func line(_ name: String, _ value: String?) -> some View {
        Text(verbatim: "\(name): \(value ?? "no data")")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func samples(_ count: Int, noun: String) -> some View {
        Text(verbatim: "n = \(count) \(noun)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
    }
}

/// The resolution switch, shared by both trend views: one question about
/// two subjects, and two switches to keep in step would be one too many.
struct TrendResolutionPicker: View {
    @Bindable var settings: Settings

    var body: some View {
        Picker("", selection: $settings.trendResolution) {
            ForEach(TrendResolution.allCases, id: \.self) { resolution in
                Text(resolution.label).tag(resolution)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// Axis wording and ticks, shared by both trend views so the two read alike.
enum TrendAxis {
    static func periodTick(_ date: Date, resolution: TrendResolution) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = resolution == .weekly ? "d MMM" : "MMM yy"
        return formatter.string(from: date)
    }

    static func periodName(_ date: Date, resolution: TrendResolution) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = resolution == .weekly ? "'Week of' d MMM yyyy" : "MMMM yyyy"
        return formatter.string(from: date)
    }

    /// Powers of ten from one upwards, thinned until they fit. Empty where
    /// the axis is linear, which leaves the chart to choose.
    static func decades(_ values: [Double], enabled: Bool) -> [Double] {
        guard enabled, let largest = values.max(), largest.isFinite, largest >= 1 else { return [] }
        let upper = Int(ceil(log10(largest)))
        var step = 1
        while upper / step > 4 { step += 1 }
        return stride(from: 0, through: upper, by: step).map { pow(10, Double($0)) }
    }

    static func number(_ value: Double) -> String {
        // Zero is a tick on every linear axis, and log10 of it is infinite:
        // converting that to a number of decimal places brought the whole
        // app down.
        guard value.isFinite, value > 0 else { return "0" }
        if value >= 1 { return "\(Int(value.rounded()))" }
        let decimals = min(6, max(1, Int(ceil(-log10(value)))))
        return String(format: "%.\(decimals)f", value)
    }
}
