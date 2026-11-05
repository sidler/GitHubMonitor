import Charts
import Combine
import SwiftUI

@MainActor
private final class RepositoryFieldModel: ObservableObject {
    @Published var draft = ""
    /// The row the pointer is over, if any.
    @Published var hovered: String?
}

/// Open pull requests per author for one repository, as a stacked bar chart.
struct DashboardView: View {
    @Bindable var state: AppState
    let controller: RefreshController

    @StateObject private var field = RepositoryFieldModel()

    /// Drafts sit on top of the ready segment: the bar's length is the whole
    /// load, and the split says how much of it is actually waiting on review.
    private enum Segment: String, Plottable {
        case ready = "Ready for review"
        case draft = "Draft"
        case awaiting = "Awaiting their review"
        case onDraft = "On a draft"
    }

    var body: some View {
        VStack(spacing: 0) {
            repositoryBar
            Divider()

            // Before the open pull requests are considered at all: these
            // two are about months of history and have a fetch of their
            // own, so a repository nobody has counted yet is not an empty
            // state for them.
            if state.settings.dashboardGrouping.isHistory {
                ReviewerStatsView(
                    state: state,
                    controller: controller,
                    bySpeed: state.settings.dashboardGrouping == .reviewSpeed
                )
            } else {
            switch state.dashboard {
            case .unconfigured:
                ContentUnavailableView(
                    "No repository chosen",
                    systemImage: "chart.bar",
                    description: Text("Pick a repository above to see its open pull requests per author.")
                )
            case .loading:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Counting pull requests…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load the repository", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { load() }
                }
            case .loaded(let data):
                switch state.settings.dashboardGrouping {
                case .reviewsGiven, .reviewSpeed:
                    EmptyView()
                case .author:
                    if data.authors.isEmpty {
                        ContentUnavailableView(
                            "No open pull requests",
                            systemImage: "chart.bar",
                            description: Text("\(data.repository) has nothing open.")
                        )
                    } else {
                        authorChart(data)
                    }
                case .reviewer:
                    if data.reviewers.isEmpty {
                        ContentUnavailableView(
                            "No outstanding reviews",
                            systemImage: "checkmark.circle",
                            description: Text("Nobody in \(data.repository) owes a review.")
                        )
                    } else {
                        reviewerChart(data)
                    }
                }
            }
            }
        }
        // Keyed on the token too: opening this view before the keychain read
        // finishes would otherwise leave it empty until the next click.
        .task(id: reloadKey) {
            field.draft = state.settings.dashboardRepository
            guard !state.settings.dashboardRepository.isEmpty else { return }
            if state.settings.dashboardGrouping.isHistory {
                // Its own fetch, and only while that side of the switch is
                // showing: it reads months of pull requests, which is not
                // something to do behind a view nobody opened.
                await controller.loadReviewerStats()
            } else if state.dashboard == .unconfigured {
                load()
            }
        }
    }

    private var reloadKey: String {
        "\(state.settings.dashboardRepository)|\(state.hasToken)"
            + "|\(state.settings.dashboardGrouping.rawValue)"
            + "|\(state.settings.reviewerStatsPeriod.rawValue)"
    }

    // MARK: - Repository picker

    private var repositoryBar: some View {
        HStack(spacing: 8) {
            Text("Repository")
                .foregroundStyle(.secondary)
            TextField("owner/repository", text: $field.draft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onSubmit { apply() }

            Button("Show") { apply() }
                .disabled(!isValid(field.draft))

            GroupingSwitch(settings: state.settings)

            // Only beside the views it means something to: how far back
            // the reviewing is counted says nothing about a chart of what
            // is open now.
            if state.settings.dashboardGrouping.isHistory {
                PeriodPicker(settings: state.settings)
            }

            // The repositories already on screen are the likely candidates,
            // and typing an exact name from memory is how you get an empty
            // chart and no idea why.
            if !suggestions.isEmpty {
                Menu("Recent") {
                    ForEach(suggestions, id: \.self) { repository in
                        Button(repository) {
                            field.draft = repository
                            apply()
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()

            if state.settings.dashboardGrouping.isHistory {
                if state.reviewerStats.isLoading {
                    ProgressView().controlSize(.small)
                } else if let data = state.reviewerStats.data {
                    Text("Read \(RelativeTime.string(for: data.fetchedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(RelativeTime.absolute(data.fetchedAt))
                }
                Button {
                    Task { await controller.loadReviewerStats(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.accessoryBar)
                .disabled(state.reviewerStats.isLoading)
                .help("Read the reviews again")
            } else if case .loaded(let data) = state.dashboard {
                Text(summaryLine(data))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.accessoryBar)
                .help("Reload the chart")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func summaryLine(_ data: DashboardData) -> String {
        let counted: String
        switch state.settings.dashboardGrouping {
        case .author:
            counted = "\(data.total) open · \(data.totalReady) ready · \(data.totalDrafts) draft"
        case .reviewer:
            counted = "\(data.totalOutstandingReviews) reviews owed by \(data.reviewers.count) reviewers"
        case .reviewsGiven, .reviewSpeed:
            // These say their own numbers in their own footer: they are
            // about months of history rather than about what is open, and
            // a count of open pull requests above them would be a figure
            // from a different question.
            return ""
        }
        // A chart adds its data up, so anything it could not read is a bar
        // that is too short rather than a row nobody scrolled to. Where that
        // happens it has to be said, next to the numbers it affects.
        guard data.unread > 0 else { return counted }
        return counted + " · \(data.unread) more not counted"
    }

    private var suggestions: [String] {
        RepositoryGrouping.repositories(
            pullRequests: state.allPullRequests,
            notifications: state.notifications,
            issues: state.allIssues
        )
    }

    private func isValid(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        // A whole-repository query needs owner and name; an owner alone would
        // search every repository they have.
        return trimmed.split(separator: "/").count == 2
    }

    private func apply() {
        let trimmed = field.draft.trimmingCharacters(in: .whitespaces)
        guard isValid(trimmed) else { return }
        state.settings.dashboardRepository = trimmed
        load()
    }

    private func load() {
        Task { await controller.loadDashboard() }
    }

    // MARK: - Chart

    private func authorChart(_ data: DashboardData) -> some View {
        // A row per author, so long logins stay readable and the chart grows
        // downwards rather than squeezing bars together.
        Chart(data.authors) { author in
            BarMark(
                x: .value("Pull requests", author.ready),
                y: .value("Author", author.author)
            )
            .foregroundStyle(by: .value("Kind", Segment.ready))
            // Once a bar is being listed, the others step back: the pane
            // describes one of them, and nothing else should look equally
            // current.
            .opacity(emphasis(for: author.id))

            BarMark(
                x: .value("Pull requests", author.drafts),
                y: .value("Author", author.author)
            )
            .foregroundStyle(by: .value("Kind", Segment.draft))
            .opacity(emphasis(for: author.id))
        }
        .chartForegroundStyleScale([
            Segment.ready: Color.accentColor,
            Segment.draft: Color.secondary.opacity(0.45),
        ])
        .chartXAxis {
            // Whole pull requests only; a tick at 2.5 would be meaningless.
            AxisMarks(values: .automatic(desiredCount: 6, roundLowerBound: true)) { value in
                if let count = value.as(Int.self) {
                    AxisGridLine()
                    AxisValueLabel { Text(verbatim: "\(count)") }
                }
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading)
        }
        .chartLegend(position: .top, alignment: .leading)
        .chartOverlay { proxy in
            pointerCatcher(proxy) { category in
                guard let author = data.authors.first(where: { $0.author == category }) else { return }
                controller.toggleWorkload(WorkloadSelection(grouping: .author, id: author.id))
            }
        }
        .overlay(alignment: .topTrailing) {
            if let author = data.authors.first(where: { $0.author == field.hovered }) {
                tooltip(
                    title: author.author,
                    lines: [
                        "\(author.ready) ready for review",
                        "\(author.drafts) draft\(author.drafts == 1 ? "" : "s")",
                        "\(author.total) open in total",
                        "Click to list them",
                    ]
                )
            }
        }
        .frame(minHeight: CGFloat(data.authors.count) * 28 + 80)
        .padding(16)
        .scrollableIfTall(rowCount: data.authors.count)
    }

    /// How many reviews each person still owes.
    private func reviewerChart(_ data: DashboardData) -> some View {
        Chart(data.reviewers) { reviewer in
            BarMark(
                x: .value("Reviews", reviewer.pending),
                y: .value("Reviewer", reviewer.reviewer)
            )
            .foregroundStyle(by: .value("Kind", Segment.awaiting))
            .opacity(emphasis(for: reviewer.id))

            BarMark(
                x: .value("Reviews", reviewer.onDrafts),
                y: .value("Reviewer", reviewer.reviewer)
            )
            .foregroundStyle(by: .value("Kind", Segment.onDraft))
            .opacity(emphasis(for: reviewer.id))
        }
        .chartForegroundStyleScale([
            Segment.awaiting: Color.orange,
            Segment.onDraft: Color.secondary.opacity(0.45),
        ])
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6, roundLowerBound: true)) { value in
                if let count = value.as(Int.self) {
                    AxisGridLine()
                    AxisValueLabel { Text(verbatim: "\(count)") }
                }
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading)
        }
        .chartLegend(position: .top, alignment: .leading)
        .chartOverlay { proxy in
            pointerCatcher(proxy) { category in
                guard
                    let reviewer = data.reviewers.first(where: { $0.reviewer == category })
                else { return }
                controller.toggleWorkload(WorkloadSelection(grouping: .reviewer, id: reviewer.id))
            }
        }
        .overlay(alignment: .topTrailing) {
            if let reviewer = data.reviewers.first(where: { $0.reviewer == field.hovered }) {
                tooltip(
                    title: reviewer.isTeam ? "\(reviewer.reviewer) (team)" : reviewer.reviewer,
                    lines: [
                        "\(reviewer.pending) awaiting their review",
                        "\(reviewer.onDrafts) on draft\(reviewer.onDrafts == 1 ? "" : "s")",
                        "\(reviewer.done) already reviewed",
                        "Click to list them",
                    ]
                )
            }
        }
        .frame(minHeight: CGFloat(data.reviewers.count) * 28 + 80)
        .padding(16)
        .scrollableIfTall(rowCount: data.reviewers.count)
    }

    // MARK: - Pointer

    /// Maps the pointer's vertical position onto a row, for the tooltip and
    /// for the click that lists the row's pull requests.
    ///
    /// Chart marks are not views: they can carry neither a `.help` tooltip
    /// nor a tap gesture of their own, so one overlay reads the category
    /// under the pointer and both behaviours hang off it. Anywhere in the
    /// row counts, not just the drawn part of the bar -- a person with one
    /// pull request would otherwise be a target a few points wide.
    private func pointerCatcher(
        _ proxy: ChartProxy,
        select: @escaping (String) -> Void
    ) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        field.hovered = category(at: location, proxy: proxy, geometry: geometry)
                    case .ended:
                        field.hovered = nil
                    }
                }
                .onTapGesture { location in
                    guard
                        let category = category(at: location, proxy: proxy, geometry: geometry)
                    else { return }
                    select(category)
                }
        }
    }

    private func category(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> String? {
        guard let plot = proxy.plotFrame else { return nil }
        return proxy.value(atY: location.y - geometry[plot].origin.y, as: String.self)
    }

    /// How present a bar should look: full while nothing is selected, and
    /// full for the selected one.
    private func emphasis(for id: String) -> Double {
        guard let selection = state.workloadSelection else { return 1 }
        return selection.id == id ? 1 : 0.35
    }

    private func tooltip(title: String, lines: [String]) -> some View {
        ChartTooltip(title: title, lines: lines)
    }
}

/// What a bar says when the pointer rests on it.
///
/// Shared by all four of the workload views, so that hovering a bar in one
/// of them looks and reads the same as in the next.
struct ChartTooltip: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        // Glass rather than a material with a hairline drawn around it:
        // this floats over the chart, which is what the system's own
        // material is for, and it brings its own edge.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

/// How far back the reviewer figures reach. Its own view for the same
/// reason the switch beside it is.
private struct PeriodPicker: View {
    @Bindable var settings: Settings

    var body: some View {
        Menu {
            Picker("Since", selection: $settings.reviewerStatsPeriod) {
                ForEach(ReviewerStatsPeriod.allCases, id: \.self) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(settings.reviewerStatsPeriod.label, systemImage: "calendar")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("How far back the reviewing is counted")
    }
}

/// The author/reviewer switch. Its own view because `settings` is a let on
/// the state and a binding needs the object itself.
private struct GroupingSwitch: View {
    @Bindable var settings: Settings

    var body: some View {
        Picker("", selection: $settings.dashboardGrouping) {
            ForEach(DashboardGrouping.allCases, id: \.self) { grouping in
                Text(grouping.label).tag(grouping)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

extension View {
    /// Long author lists need to scroll; short ones should not sit in a
    /// scroll view that scrolls a pixel.
    @ViewBuilder
    func scrollableIfTall(rowCount: Int) -> some View {
        if rowCount > 12 {
            ScrollView { self }
        } else {
            self
        }
    }
}
