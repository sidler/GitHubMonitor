import Foundation

/// What the sidebar is pointing at.
///
/// A repository of nil means "everything in this section"; a repository name
/// narrows the list to that one, which is what the per-repository entries
/// under each heading select.
public enum SidebarSelection: Hashable, Sendable {
    case pullRequests(repository: String?)
    /// Pull requests the user opened, waiting on other people.
    case myPullRequests(repository: String?)
    /// Issues assigned to the user.
    case myIssues(repository: String?)
    case mentions(repository: String?)
    case dashboard
    /// Delivery over time, as opposed to the dashboard's snapshot of who is
    /// carrying what right now.
    case trends
    /// The same questions, asked about one's own pull requests.
    case myTrends
    case settings

    public var tab: MainWindowTab {
        switch self {
        case .pullRequests: .pullRequests
        case .myPullRequests: .myPullRequests
        case .myIssues: .myIssues
        case .mentions: .mentions
        case .dashboard: .dashboard
        case .trends: .trends
        case .myTrends: .myTrends
        case .settings: .settings
        }
    }

    /// The repository this selection narrows to, if any.
    public var repository: String? {
        switch self {
        case .pullRequests(let repository),
             .myPullRequests(let repository),
             .myIssues(let repository),
             .mentions(let repository): repository
        case .dashboard, .trends, .myTrends, .settings: nil
        }
    }

    /// Which watched list this points at, if any. "My Pull Requests" and
    /// the views below the lists have no switch, so they answer nil.
    public var watchedList: WatchedList? {
        switch self {
        case .pullRequests: .reviews
        case .myIssues: .issues
        case .mentions: .mentions
        case .myPullRequests, .dashboard, .trends, .myTrends, .settings: nil
        }
    }

    /// The "All" entry for one list, as the sidebar tags it.
    public static func all(_ list: WatchedList) -> SidebarSelection {
        switch list {
        case .reviews: .pullRequests(repository: nil)
        case .issues: .myIssues(repository: nil)
        case .mentions: .mentions(repository: nil)
        }
    }

    public var isMentions: Bool {
        if case .mentions = self { return true }
        return false
    }

    /// Heading for the list being shown, in the style of Finder's toolbar
    /// title: the repository when one is chosen, the section otherwise.
    public var title: String {
        switch self {
        case .pullRequests(let repository): repository ?? "Reviews Requested"
        case .myPullRequests(let repository): repository ?? "My Pull Requests"
        case .myIssues(let repository): repository ?? "My Issues"
        case .mentions(let repository): repository ?? "Mentions"
        case .dashboard: "Workload"
        case .trends: "Trends"
        case .myTrends: "My Trends"
        case .settings: "Settings"
        }
    }

    /// Secondary line, so a repository selection still says what it is
    /// showing.
    public var subtitle: String? {
        switch self {
        case .pullRequests(let repository): repository == nil ? nil : "Reviews Requested"
        case .myPullRequests(let repository): repository == nil ? nil : "My Pull Requests"
        case .myIssues(let repository): repository == nil ? nil : "My Issues"
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
}
