import Foundation

/// Narrows unread notifications to the reasons the user cares about.
public enum NotificationFilter {
    public static func apply(
        _ items: [NotificationItem],
        reasons: Set<NotificationReason>,
        repositoryFilters: [String]
    ) -> [NotificationItem] {
        let matching = matchingRepositories(items, repositoryFilters: repositoryFilters)
        // An empty selection means "nothing selected", not "everything":
        // the reasons are checkboxes, and unticking them all should silence
        // the badge rather than open it up.
        return matching.filter { reasons.contains($0.reason) }
    }

    static func matchingRepositories(
        _ items: [NotificationItem],
        repositoryFilters: [String]
    ) -> [NotificationItem] {
        let filters = repositoryFilters
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !filters.isEmpty else { return items }

        return items.filter { item in
            let repository = item.repository.lowercased()
            return filters.contains { repository == $0 || repository.hasPrefix($0 + "/") }
        }
    }
}
