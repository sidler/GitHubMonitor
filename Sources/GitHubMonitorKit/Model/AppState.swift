import Foundation
import Observation

public enum MainWindowTab: String, Hashable, CaseIterable, Sendable {
    case pullRequests
    case mentions
    case settings

    public var label: String {
        switch self {
        case .pullRequests: "Pull Requests"
        case .mentions: "Mentions"
        case .settings: "Settings"
        }
    }

    public var symbolName: String {
        switch self {
        case .pullRequests: "arrow.triangle.pull"
        case .mentions: "bell"
        case .settings: "gearshape"
        }
    }
}

public enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(Date)
    case failed(String)
}

/// Single source of truth shared by the status item, the popover and the
/// main window.
@MainActor
@Observable
public final class AppState {
    public let settings: Settings

    public var pullRequests: [PullRequestItem] = []
    public var notifications: [NotificationItem] = []
    public var loadState: LoadState = .idle
    /// True once a token has been found in the Keychain.
    public var hasToken: Bool = false
    public var selectedTab: MainWindowTab = .pullRequests

    public init(settings: Settings) {
        self.settings = settings
    }

    /// Pull requests after every filter -- what the list shows and what the
    /// menu bar counts. Both read this so they cannot drift apart.
    public var visiblePullRequests: [PullRequestItem] {
        PullRequestFilter.apply(
            pullRequests,
            includeDrafts: settings.includeDrafts,
            repositoryFilters: settings.repositoryFilters
        )
    }

    /// Drafts within the repository filter, whether or not they are shown.
    /// Drives the wording of the draft toggle.
    public var draftCount: Int {
        PullRequestFilter
            .matchingRepositories(pullRequests, repositoryFilters: settings.repositoryFilters)
            .count { $0.isDraft }
    }

    public var health: StatusBarHealth {
        guard hasToken else { return .unconfigured }
        if case .failed = loadState { return .failing }
        return .ok
    }

    public var statusMessage: String {
        switch loadState {
        case .idle: "Not refreshed yet"
        case .loading: "Refreshing…"
        case .loaded(let date): "Updated \(RelativeTime.string(for: date))"
        case .failed(let message): message
        }
    }

    /// Placeholder content for stage 1, so the menu bar rendering and the two
    /// UIs can be exercised before the API clients exist.
    public func loadSampleData() {
        hasToken = true
        pullRequests = [
            PullRequestItem(
                id: "1", number: 482, title: "Fix race condition in session handler",
                repository: "octo/server", author: "mira",
                url: URL(string: "https://github.com")!, isDraft: false,
                updatedAt: .now.addingTimeInterval(-3600),
                reviewDecision: .reviewRequired, checks: .success
            ),
            PullRequestItem(
                id: "2", number: 77, title: "Add PSR-12 ruleset to CI",
                repository: "octo/website", author: "arun",
                url: URL(string: "https://github.com")!, isDraft: true,
                updatedAt: .now.addingTimeInterval(-86400 * 3),
                reviewDecision: .changesRequested, checks: .failure
            ),
            PullRequestItem(
                id: "3", number: 1204, title: "Bump dependencies for PHP 8.4",
                repository: "octo/toolkit", author: "dara",
                url: URL(string: "https://github.com")!, isDraft: false,
                updatedAt: .now.addingTimeInterval(-600),
                reviewDecision: .reviewRequired, checks: .pending
            ),
        ]
        notifications = [
            NotificationItem(
                id: "n1", title: "Can you take a look at the migration order?",
                repository: "octo/server", reason: .mention,
                updatedAt: .now.addingTimeInterval(-1800),
                subjectType: "Issue", latestCommentAPIURL: nil, subjectAPIURL: nil
            ),
            NotificationItem(
                id: "n2", title: "Release 8.2 checklist",
                repository: "octo/toolkit", reason: .teamMention,
                updatedAt: .now.addingTimeInterval(-7200),
                subjectType: "Issue", latestCommentAPIURL: nil, subjectAPIURL: nil
            ),
        ]
        loadState = .loaded(.now)
    }
}
