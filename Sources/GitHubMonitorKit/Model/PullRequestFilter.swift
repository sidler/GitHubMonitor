import Foundation

/// Narrows the fetched items down to what the user wants counted.
///
/// Applied here rather than written into the GitHub query, so the count in
/// the menu bar can never disagree with the list below it -- and so a change
/// takes effect without another round trip. Drafts are filtered the same way
/// but against the list that holds them, which is where that switch now
/// lives.
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
}
