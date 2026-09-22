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

    /// Only count pull requests, issues and mentions in these "owner" or
    /// "owner/repo" scopes. Empty means no restriction.
    public var repositoryFilters: [String] {
        didSet { store.set(repositoryFilters, forKey: Key.repositoryFilters) }
    }

    public var includeDrafts: Bool {
        didSet { store.set(includeDrafts, forKey: Key.includeDrafts) }
    }

    /// The lists in the sidebar, in the order they appear there.
    ///
    /// Seeded on first launch with what the app used to hard-code, under
    /// fixed ids, so the settings written before lists were editable --
    /// which of them the menu bar counts, how each was sorted and grouped --
    /// carry over to them.
    public var savedLists: [SavedList] {
        didSet { store.set(Self.encode(savedLists), forKey: Key.savedLists) }
    }

    /// Which of the lists appear in the menu bar, the popover and
    /// the window. Everything is shown until it is switched off.
    public var listVisibility: ListVisibility {
        didSet { store.set(listVisibility.storedKeys, forKey: Key.hiddenLists) }
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

    /// What the mentions are called and which icon they wear.
    ///
    /// They are not a saved list -- they come from the notifications API
    /// rather than a search -- but they sit among the lists everywhere they
    /// appear, and there is no reason for the one entry nobody can label to
    /// be the one the app named itself.
    public var mentionsTitle: String {
        didSet { store.set(mentionsTitle, forKey: Key.mentionsTitle) }
    }

    public var mentionsSymbol: String {
        didSet { store.set(mentionsSymbol, forKey: Key.mentionsSymbol) }
    }

    /// The mentions' grouping. Not part of a list: they are not a search,
    /// and they group by the kind of thing a notification is about.
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
        if let raw = store.stringArray(forKey: Key.notificationReasons) {
            notificationReasons = Set(raw.map(NotificationReason.init(apiValue:)))
        } else {
            notificationReasons = [.mention, .teamMention]
        }
        listVisibility = ListVisibility(
            storedKeys: store.stringArray(forKey: Key.hiddenLists) ?? []
        )
        let storedGrouping =
            (store.string(forKey: Key.listGrouping).flatMap(ListGrouping.init(rawValue:))) ?? .flat
        savedLists = Self.withoutTeamPlaceholder(
            Self.decode(store.data(forKey: Key.savedLists))
        ) ?? SavedList.seeds(
            grouping: storedGrouping,
            issueSettings: (
                (store.string(forKey: Key.issueGrouping).flatMap(ListGrouping.init(rawValue:))) ?? .flat,
                (store.string(forKey: Key.issueSort).flatMap(ListSort.init(rawValue:))) ?? .updated,
                Set(store.stringArray(forKey: Key.hiddenIssueTypes) ?? [])
            )
        )
        dashboardRepository = store.string(forKey: Key.dashboardRepository) ?? ""
        dashboardGrouping =
            (store.string(forKey: Key.dashboardGrouping).flatMap(DashboardGrouping.init(rawValue:))) ?? .author
        launchAtLogin = store.object(forKey: Key.launchAtLogin) as? Bool ?? false
        notificationGrouping =
            (store.string(forKey: Key.notificationGrouping).flatMap(ListGrouping.init(rawValue:))) ?? .flat
        mentionsTitle = store.string(forKey: Key.mentionsTitle) ?? "Mentions"
        mentionsSymbol = store.string(forKey: Key.mentionsSymbol)
            ?? StatusBarTitleBuilder.mentionSymbol
        trendResolution =
            (store.string(forKey: Key.trendResolution).flatMap(TrendResolution.init(rawValue:))) ?? .weekly
        trendsIncludeBots = store.object(forKey: Key.trendsIncludeBots) as? Bool ?? false
        commenterScope =
            (store.string(forKey: Key.commenterScope).flatMap(CommenterScope.init(rawValue:))) ?? .mine
    }

    // MARK: - Lists

    /// Replaces one list, by id. The array is rewritten wholesale so the
    /// stored value stays a single document.
    public func update(_ list: SavedList) {
        guard let index = savedLists.firstIndex(where: { $0.id == list.id }) else { return }
        savedLists[index] = list
    }

    public func list(withID id: String) -> SavedList? {
        savedLists.first { $0.id == id }
    }

    /// Drops the line that used to be expanded into one search per team.
    ///
    /// `review-requested:` covers the teams one is on -- GitHub resolves the
    /// membership itself -- so the second line was asking twice. It is
    /// removed rather than left in place because nothing expands `@myteams`
    /// any more, and a line with a placeholder still in it is a search that
    /// can only fail.
    nonisolated static func withoutTeamPlaceholder(_ lists: [SavedList]?) -> [SavedList]? {
        guard let lists else { return nil }
        return lists.map { list in
            let kept = list.queryLines.filter { !$0.contains("@myteams") }
            guard kept.count != list.queryLines.count else { return list }
            var updated = list
            updated.query = kept.joined(separator: "\n")
            return updated
        }
    }

    nonisolated static func encode(_ lists: [SavedList]) -> Data {
        (try? JSONEncoder().encode(lists)) ?? Data()
    }

    nonisolated static func decode(_ data: Data?) -> [SavedList]? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([SavedList].self, from: data)
    }

    private enum Key {
        static let statusBarStyle = "statusBarStyle"
        static let refreshInterval = "refreshInterval"
        static let repositoryFilters = "repositoryFilters"
        static let includeDrafts = "includeDrafts"
        static let notificationReasons = "notificationReasons"
        static let hiddenLists = "hiddenLists"
        static let savedLists = "savedLists"
        static let dashboardRepository = "dashboardRepository"
        static let dashboardGrouping = "dashboardGrouping"
        static let launchAtLogin = "launchAtLogin"
        // Read once, to seed the lists on the first launch after they
        // became editable; never written again.
        static let listGrouping = "listGrouping"
        static let notificationGrouping = "notificationGrouping"
        static let mentionsTitle = "mentionsTitle"
        static let mentionsSymbol = "mentionsSymbol"
        static let pullRequestSort = "pullRequestSort"
        static let issueGrouping = "issueGrouping"
        static let issueSort = "issueSort"
        static let hiddenIssueTypes = "hiddenIssueTypes"
        static let trendResolution = "trendResolution"
        static let trendsIncludeBots = "trendsIncludeBots"
        static let commenterScope = "commenterScope"
    }
}
