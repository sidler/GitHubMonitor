import Foundation

/// What the sidebar is pointing at.
///
/// A repository of nil means "everything in this section"; a repository name
/// narrows the list to that one, which is what the per-repository entries
/// under each heading select.
public enum SidebarSelection: Hashable, Sendable {
    /// One of the saved lists, by id.
    case list(id: String, repository: String?)
    case mentions(repository: String?)
    case dashboard
    /// Delivery over time, as opposed to the dashboard's snapshot of who is
    /// carrying what right now.
    case trends
    /// The same questions, asked about one's own pull requests.
    case myTrends
    case settings

    /// The repository this selection narrows to, if any.
    public var repository: String? {
        switch self {
        case .list(_, let repository), .mentions(let repository): repository
        case .dashboard, .trends, .myTrends, .settings: nil
        }
    }

    /// Which saved list this points at, if any.
    public var listID: String? {
        switch self {
        case .list(let id, _): id
        case .mentions, .dashboard, .trends, .myTrends, .settings: nil
        }
    }

    /// The key the visibility switches know this entry by.
    public var visibilityKey: String? {
        switch self {
        case .list(let id, _): id
        case .mentions: ListVisibility.mentionsKey
        case .dashboard, .trends, .myTrends, .settings: nil
        }
    }

    /// Whether this view puts anything in the toolbar.
    ///
    /// An empty toolbar item is not nothing on macOS 26: the system draws
    /// every item its own glass background, so a view with no controls left
    /// a bare sliver of glass in the corner.
    public var hasToolbarControls: Bool {
        switch self {
        case .list, .mentions: true
        case .dashboard, .trends, .myTrends, .settings: false
        }
    }

    public var isMentions: Bool {
        if case .mentions = self { return true }
        return false
    }

    /// Heading for what is being shown, in the style of Finder's toolbar
    /// title: the repository when one is chosen, the section otherwise.
    ///
    /// A list's own title is not in here: the selection knows only its id,
    /// and the title lives in the list. `AppState.selectionTitle` puts the
    /// two together.
    public var fixedTitle: String? {
        switch self {
        case .list: nil
        case .mentions(let repository): repository ?? "Mentions"
        case .dashboard: "Workload"
        case .trends: "Trends"
        case .myTrends: "My Trends"
        case .settings: "Settings"
        }
    }

    public var fixedSubtitle: String? {
        switch self {
        case .list: nil
        case .mentions(let repository): repository == nil ? nil : "Mentions"
        case .dashboard, .trends, .myTrends, .settings: nil
        }
    }
}

/// A repository entry in the sidebar.
public struct SidebarRepository: Identifiable, Hashable, Sendable {
    public var id: String { repository }
    public let repository: String
    public let count: Int

    /// The rows a sidebar section actually draws.
    ///
    /// One repository is the case the setting is for: the row repeats what
    /// "All" above it already counts, and every section that has it costs a
    /// line of a column that is narrow to begin with.
    public static func rows(
        _ repositories: [SidebarRepository], collapsingSingle: Bool
    ) -> [SidebarRepository] {
        collapsingSingle && repositories.count == 1 ? [] : repositories
    }
}
