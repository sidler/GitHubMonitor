import Foundation

/// Where a list of this app's lives on github.com.
///
/// The same search, in the browser: for the things this app deliberately
/// does not do -- editing a query by hand, bulk actions, or simply
/// showing somebody else what you are looking at.
///
/// Built from `ListQuery.searches` rather than from the saved text, so
/// the link and the list cannot disagree: the global repository filter
/// and a relative date like "closed in the last week" are already
/// resolved in what the app asked GitHub for, and the browser gets
/// exactly that.
public enum GitHubSearchLink {
    /// The query with every repository or organisation qualifier replaced
    /// by one repository.
    ///
    /// Replaced, not added. GitHub reads repeated `repo:` and `org:`
    /// qualifiers as alternatives, so appending one to a query that
    /// already names repositories would widen the search at the moment
    /// somebody asked to narrow it -- the sidebar's per-repository entry
    /// says "only this one".
    ///
    /// Split on whitespace and rejoined: a qualifier with a quoted value,
    /// `label:"needs decision"`, comes through unchanged because nothing
    /// between the pieces is altered.
    public static func narrowed(_ query: String, to repository: String) -> String {
        let kept = query
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.hasPrefix("repo:") && !$0.hasPrefix("org:") }
        return (kept + ["repo:\(repository)"]).joined(separator: " ")
    }

    /// Where this list is on github.com, narrowed the way the sidebar
    /// narrows it.
    ///
    /// A list may stand on more than one search -- GitHub's own search
    /// cannot express their union in one query, so this is the first of
    /// them, and `searchCount` is what lets a caller say so.
    public static func address(
        for list: SavedList,
        repositoryFilters: [String],
        narrowedTo repository: String? = nil
    ) -> URL? {
        let searches = ListQuery.searches(for: list, repositoryFilters: repositoryFilters)
        guard let search = searches.first else { return nil }

        let query = repository.map { narrowed(search.query, to: $0) } ?? search.query
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        var components = URLComponents(string: "https://github.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: type(of: list.content)),
        ]
        return components?.url
    }

    /// How many searches the list stands on, so a button can say that it
    /// is opening one of several rather than all of them.
    public static func searchCount(
        for list: SavedList, repositoryFilters: [String]
    ) -> Int {
        ListQuery.searches(for: list, repositoryFilters: repositoryFilters).count
    }

    /// What GitHub calls the tab this search belongs in.
    private static func type(of content: ListContent) -> String {
        switch content {
        case .pullRequests: "pullrequests"
        case .issues: "issues"
        }
    }
}
