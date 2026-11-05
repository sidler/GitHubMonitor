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
                        WorkloadTableView(state: state, controller: controller, data: data, byReviewer: false)
                    }
                case .reviewer:
                    if data.reviewers.isEmpty {
                        ContentUnavailableView(
                            "No outstanding reviews",
                            systemImage: "checkmark.circle",
                            description: Text("Nobody in \(data.repository) owes a review.")
                        )
                    } else {
                        WorkloadTableView(state: state, controller: controller, data: data, byReviewer: true)
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
                    if let data = state.reviewerStats.data {
                        // A month at a time, said out loud: the table
                        // fills in as they land, and a number that moves
                        // is the difference between waiting and worrying.
                        Text("\(data.months.done) of \(data.months.of) months")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
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
            } else if case .loaded = state.dashboard {
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
