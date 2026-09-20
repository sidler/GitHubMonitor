import Foundation

/// What the sidebar is pointing at.
///
/// A repository of nil means "everything in this section"; a repository name
/// narrows the list to that one, which is what the per-repository entries
/// under each heading select.
public enum SidebarSelection: Hashable, Sendable {
    case pullRequests(repository: String?)
    case mentions(repository: String?)
    case settings

    public var tab: MainWindowTab {
        switch self {
        case .pullRequests: .pullRequests
        case .mentions: .mentions
        case .settings: .settings
        }
    }

    /// The repository this selection narrows to, if any.
    public var repository: String? {
        switch self {
        case .pullRequests(let repository), .mentions(let repository): repository
        case .settings: nil
        }
    }

    /// Heading for the list being shown, in the style of Finder's toolbar
    /// title: the repository when one is chosen, the section otherwise.
    public var title: String {
        switch self {
        case .pullRequests(let repository): repository ?? "Pull Requests"
        case .mentions(let repository): repository ?? "Mentions"
        case .settings: "Settings"
        }
    }

    /// Secondary line, so a repository selection still says what it is
    /// showing.
    public var subtitle: String? {
        switch self {
        case .pullRequests(let repository): repository == nil ? nil : "Pull Requests"
        case .mentions(let repository): repository == nil ? nil : "Mentions"
        case .settings: nil
        }
    }
}

/// A repository entry in the sidebar.
public struct SidebarRepository: Identifiable, Hashable, Sendable {
    public var id: String { repository }
    public let repository: String
    public let count: Int
}
