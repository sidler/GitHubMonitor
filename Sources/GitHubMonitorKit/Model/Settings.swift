import Foundation
import Observation

/// User-visible configuration, persisted in UserDefaults. The token itself is
/// never stored here -- it lives in the Keychain.
@MainActor
@Observable
public final class Settings {
    /// GitHub asks clients to poll no faster than its `X-Poll-Interval`
    /// header, typically 60s. We treat the user's interval as "no more often
    /// than this" and never go below the floor.
    public static let minimumRefreshInterval: TimeInterval = 60

    public var statusBarStyle: StatusBarStyle {
        didSet { store.set(statusBarStyle.rawValue, forKey: Key.statusBarStyle) }
    }

    /// Seconds between automatic refreshes, never below the floor.
    ///
    /// Clamped in this setter rather than in a `didSet` on the stored
    /// property. Assigning to a property from inside its own observer
    /// re-enters the setter that `@Observable` generates for it, which calls
    /// the observer again: changing the interval in settings crashed on the
    /// overflowing stack.
    public var refreshInterval: TimeInterval {
        get { storedRefreshInterval }
        set { storedRefreshInterval = max(Self.minimumRefreshInterval, newValue) }
    }

    private var storedRefreshInterval: TimeInterval {
        didSet { store.set(storedRefreshInterval, forKey: Key.refreshInterval) }
    }

    /// Only count pull requests in these "owner" or "owner/repo" scopes.
    /// Empty means no restriction.
    public var repositoryFilters: [String] {
        didSet { store.set(repositoryFilters, forKey: Key.repositoryFilters) }
    }

    public var includeDrafts: Bool {
        didSet { store.set(includeDrafts, forKey: Key.includeDrafts) }
    }

    /// "org/team" slugs whose review requests also count as mine.
    public var teamSlugs: [String] {
        didSet { store.set(teamSlugs, forKey: Key.teamSlugs) }
    }

    /// Notification reasons that count towards the mention badge.
    public var notificationReasons: Set<NotificationReason> {
        didSet {
            store.set(notificationReasons.map(\.rawValue), forKey: Key.notificationReasons)
        }
    }

    /// Repository the dashboard charts. Empty until one is chosen.
    public var dashboardRepository: String {
        didSet { store.set(dashboardRepository, forKey: Key.dashboardRepository) }
    }

    /// Whether the dashboard charts authors or reviewers.
    public var dashboardGrouping: DashboardGrouping {
        didSet { store.set(dashboardGrouping.rawValue, forKey: Key.dashboardGrouping) }
    }

    /// Whether the trend charts are drawn per week or per month.
    public var trendResolution: TrendResolution {
        didSet { store.set(trendResolution.rawValue, forKey: Key.trendResolution) }
    }

    /// Whether pull requests opened by bots count towards the trends.
    /// Off by default: renovate and its kind are handled differently from
    /// people's pull requests and would dominate both counts and durations.
    public var trendsIncludeBots: Bool {
        didSet { store.set(trendsIncludeBots, forKey: Key.trendsIncludeBots) }
    }

    /// Whether the commenter ranking covers your own pull requests or the
    /// whole dashboard repository.
    public var commenterScope: CommenterScope {
        didSet { store.set(commenterScope.rawValue, forKey: Key.commenterScope) }
    }

    public var launchAtLogin: Bool {
        didSet { store.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    /// How the pull request list is split up.
    public var listGrouping: ListGrouping {
        didSet { store.set(listGrouping.rawValue, forKey: Key.listGrouping) }
    }

    /// What the pull request lists are ordered by. Shared by both of them:
    /// they answer the same question about different pull requests.
    public var pullRequestSort: PullRequestSort {
        didSet { store.set(pullRequestSort.rawValue, forKey: Key.pullRequestSort) }
    }

    /// Kept separate from the pull request grouping: the lists offer
    /// different options, and choosing "by type" for notifications should not
    /// silently reset how pull requests are shown.
    public var notificationGrouping: ListGrouping {
        didSet { store.set(notificationGrouping.rawValue, forKey: Key.notificationGrouping) }
    }

    private let store: UserDefaults

    public init(store: UserDefaults = .standard) {
        self.store = store
        statusBarStyle =
            (store.string(forKey: Key.statusBarStyle).flatMap(StatusBarStyle.init(rawValue:))) ?? .separate
        let saved = store.double(forKey: Key.refreshInterval)
        storedRefreshInterval = saved > 0 ? max(Self.minimumRefreshInterval, saved) : 300
        repositoryFilters = store.stringArray(forKey: Key.repositoryFilters) ?? []
        includeDrafts = store.object(forKey: Key.includeDrafts) as? Bool ?? false
        teamSlugs = store.stringArray(forKey: Key.teamSlugs) ?? []
        if let raw = store.stringArray(forKey: Key.notificationReasons) {
            notificationReasons = Set(raw.map(NotificationReason.init(apiValue:)))
        } else {
            notificationReasons = [.mention, .teamMention]
        }
        dashboardRepository = store.string(forKey: Key.dashboardRepository) ?? ""
        dashboardGrouping =
            (store.string(forKey: Key.dashboardGrouping).flatMap(DashboardGrouping.init(rawValue:))) ?? .author
        launchAtLogin = store.object(forKey: Key.launchAtLogin) as? Bool ?? false
        listGrouping =
            (store.string(forKey: Key.listGrouping).flatMap(ListGrouping.init(rawValue:))) ?? .flat
        notificationGrouping =
            (store.string(forKey: Key.notificationGrouping).flatMap(ListGrouping.init(rawValue:))) ?? .flat
        pullRequestSort =
            (store.string(forKey: Key.pullRequestSort).flatMap(PullRequestSort.init(rawValue:))) ?? .updated
        trendResolution =
            (store.string(forKey: Key.trendResolution).flatMap(TrendResolution.init(rawValue:))) ?? .weekly
        trendsIncludeBots = store.object(forKey: Key.trendsIncludeBots) as? Bool ?? false
        commenterScope =
            (store.string(forKey: Key.commenterScope).flatMap(CommenterScope.init(rawValue:))) ?? .mine
    }

    private enum Key {
        static let statusBarStyle = "statusBarStyle"
        static let refreshInterval = "refreshInterval"
        static let repositoryFilters = "repositoryFilters"
        static let includeDrafts = "includeDrafts"
        static let teamSlugs = "teamSlugs"
        static let notificationReasons = "notificationReasons"
        static let dashboardRepository = "dashboardRepository"
        static let dashboardGrouping = "dashboardGrouping"
        static let launchAtLogin = "launchAtLogin"
        static let listGrouping = "listGrouping"
        static let notificationGrouping = "notificationGrouping"
        static let pullRequestSort = "pullRequestSort"
        static let trendResolution = "trendResolution"
        static let trendsIncludeBots = "trendsIncludeBots"
        static let commenterScope = "commenterScope"
    }
}
