import Charts
import Combine
import SwiftUI

@MainActor
private final class RepositoryFieldModel: ObservableObject {
    @Published var draft = ""
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
        // Keyed on the token too: opening this view before the keychain read
        // finishes would otherwise leave it empty until the next click.
        .task(id: reloadKey) {
            field.draft = state.settings.dashboardRepository
            if !state.settings.dashboardRepository.isEmpty, state.dashboard == .unconfigured {
                load()
            }
        }
    }

    private var reloadKey: String {
        "\(state.settings.dashboardRepository)|\(state.hasToken)"
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

            if case .loaded(let data) = state.dashboard {
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
        switch state.settings.dashboardGrouping {
        case .author:
            "\(data.total) open · \(data.totalReady) ready · \(data.totalDrafts) draft"
        case .reviewer:
            "\(data.totalOutstandingReviews) reviews owed by \(data.reviewers.count) reviewers"
        }
    }

    private var suggestions: [String] {
        RepositoryGrouping.repositories(
            pullRequests: state.pullRequests + state.authoredPullRequests,
            notifications: state.notifications
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

            BarMark(
                x: .value("Pull requests", author.drafts),
                y: .value("Author", author.author)
            )
            .foregroundStyle(by: .value("Kind", Segment.draft))
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

            BarMark(
                x: .value("Reviews", reviewer.onDrafts),
                y: .value("Reviewer", reviewer.reviewer)
            )
            .foregroundStyle(by: .value("Kind", Segment.onDraft))
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
        .frame(minHeight: CGFloat(data.reviewers.count) * 28 + 80)
        .padding(16)
        .scrollableIfTall(rowCount: data.reviewers.count)
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

private extension View {
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
