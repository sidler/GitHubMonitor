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

    /// Seconds between automatic refreshes.
    public var refreshInterval: TimeInterval {
        didSet {
            refreshInterval = max(Self.minimumRefreshInterval, refreshInterval)
            store.set(refreshInterval, forKey: Key.refreshInterval)
        }
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

    public var launchAtLogin: Bool {
        didSet { store.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    /// How the pull request list is split up.
    public var listGrouping: ListGrouping {
        didSet { store.set(listGrouping.rawValue, forKey: Key.listGrouping) }
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
        let storedInterval = store.double(forKey: Key.refreshInterval)
        refreshInterval = storedInterval > 0 ? max(Self.minimumRefreshInterval, storedInterval) : 300
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
    }
}
