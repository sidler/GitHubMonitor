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

    public var launchAtLogin: Bool {
        didSet { store.set(launchAtLogin, forKey: Key.launchAtLogin) }
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
        launchAtLogin = store.object(forKey: Key.launchAtLogin) as? Bool ?? false
    }

    private enum Key {
        static let statusBarStyle = "statusBarStyle"
        static let refreshInterval = "refreshInterval"
        static let repositoryFilters = "repositoryFilters"
        static let includeDrafts = "includeDrafts"
        static let teamSlugs = "teamSlugs"
        static let notificationReasons = "notificationReasons"
        static let launchAtLogin = "launchAtLogin"
    }
}
