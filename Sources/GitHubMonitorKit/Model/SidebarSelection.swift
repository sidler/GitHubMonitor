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
    case mentions(repository: String?)
    case dashboard
    case settings

    public var tab: MainWindowTab {
        switch self {
        case .pullRequests: .pullRequests
        case .myPullRequests: .myPullRequests
        case .mentions: .mentions
        case .dashboard: .dashboard
        case .settings: .settings
        }
    }

    /// The repository this selection narrows to, if any.
    public var repository: String? {
        switch self {
        case .pullRequests(let repository),
             .myPullRequests(let repository),
             .mentions(let repository): repository
        case .dashboard, .settings: nil
        }
    }

    /// Heading for the list being shown, in the style of Finder's toolbar
    /// title: the repository when one is chosen, the section otherwise.
    public var title: String {
        switch self {
        case .pullRequests(let repository): repository ?? "Reviews Requested"
        case .myPullRequests(let repository): repository ?? "My Pull Requests"
        case .mentions(let repository): repository ?? "Mentions"
        case .dashboard: "Dashboard"
        case .settings: "Settings"
        }
    }

    /// Secondary line, so a repository selection still says what it is
    /// showing.
    public var subtitle: String? {
        switch self {
        case .pullRequests(let repository): repository == nil ? nil : "Reviews Requested"
        case .myPullRequests(let repository): repository == nil ? nil : "My Pull Requests"
        case .mentions(let repository): repository == nil ? nil : "Mentions"
        case .dashboard, .settings: nil
        }
    }
}

/// A repository entry in the sidebar.
public struct SidebarRepository: Identifiable, Hashable, Sendable {
    public var id: String { repository }
    public let repository: String
    public let count: Int
}
