import Foundation

/// Narrows the fetched items down to what the user wants counted.
///
/// Drafts are filtered here rather than in the GitHub query so the toggle in
/// the list takes effect immediately, without another round trip. The
/// repository filter is applied here too, so the count in the menu bar can
/// never disagree with the list below it.
public enum PullRequestFilter {
    /// Applies the repository filter only -- the population the draft toggle
    /// talks about.
    public static func matchingRepositories<Item: ListedItem>(
        _ items: [Item],
        repositoryFilters: [String]
    ) -> [Item] {
        let filters = repositoryFilters
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !filters.isEmpty else { return items }

        return items.filter { item in
            let repository = item.repository.lowercased()
            return filters.contains { filter in
                // A bare owner matches everything below it; "owner/name"
                // matches that one repository.
                repository == filter || repository.hasPrefix(filter + "/")
            }
        }
    }

    public static func apply(
        _ items: [PullRequestItem],
        includeDrafts: Bool,
        repositoryFilters: [String]
    ) -> [PullRequestItem] {
        let matching = matchingRepositories(items, repositoryFilters: repositoryFilters)
        return includeDrafts ? matching : matching.filter { !$0.isDraft }
    }
}
