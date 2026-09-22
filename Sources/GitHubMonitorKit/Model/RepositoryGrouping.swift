import Foundation

/// How the main window lays its lists out.
public enum ListGrouping: String, CaseIterable, Codable, Sendable {
    case flat
    case byRepository
    /// Only meaningful for notifications; a list of pull requests is all one
    /// type by definition.
    case byType

    public var label: String {
        switch self {
        case .flat: "All"
        case .byRepository: "By repository"
        case .byType: "By type"
        }
    }

    public static let forPullRequests: [ListGrouping] = [.flat, .byRepository]
    public static let forNotifications: [ListGrouping] = [.flat, .byRepository, .byType]
}

/// One group's worth of items, keyed by whatever it was grouped on.
public struct RepositoryGroup<Item>: Identifiable {
    public var id: String { repository }
    /// The group's heading: a repository name, or a subject type.
    public let repository: String
    public let items: [Item]
}

public enum RepositoryGrouping {
    /// Groups items by repository, preserving the order within each group.
    ///
    /// Groups are ordered by size first so the repository demanding most
    /// attention is at the top, then by name so the order is stable when
    /// sizes match.
    public static func group<Item>(
        _ items: [Item],
        by repository: (Item) -> String
    ) -> [RepositoryGroup<Item>] {
        var order: [String] = []
        var buckets: [String: [Item]] = [:]

        for item in items {
            let key = repository(item)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(item)
        }

        return order
            .map { RepositoryGroup(repository: $0, items: buckets[$0] ?? []) }
            .sorted { lhs, rhs in
                lhs.items.count == rhs.items.count
                    ? lhs.repository.localizedStandardCompare(rhs.repository) == .orderedAscending
                    : lhs.items.count > rhs.items.count
            }
    }

    /// Repositories present in the given items, for offering as filters.
    ///
    /// Every list contributes: a repository the user only has issues in is
    /// as good a filter as one they review in, and offering half of them
    /// would leave the other half to be typed from memory.
    public static func repositories(
        pullRequests: [PullRequestItem],
        notifications: [NotificationItem],
        issues: [IssueItem] = []
    ) -> [String] {
        let names = Set(pullRequests.map(\.repository))
            .union(notifications.map(\.repository))
            .union(issues.map(\.repository))
        return names
            .filter { $0 != "?" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The owners behind those repositories, so a whole organisation can be
    /// filtered in one entry rather than repository by repository.
    public static func owners(of repositories: [String]) -> [String] {
        let owners = repositories.compactMap { $0.split(separator: "/").first.map(String.init) }
        return Set(owners).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
