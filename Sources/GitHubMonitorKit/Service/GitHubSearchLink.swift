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
    /// `/pulls/search` and `/issues/search` rather than `/search?type=`:
    /// those are the pages GitHub itself links to, they keep the tab and
    /// the filter bar somebody expects to carry on working in, and the
    /// generic search page did not answer the way this app's queries
    /// expect.
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

        // The order the terms are written in does not matter to GitHub.
        // This one is chosen to read the way the list does: how it is
        // sorted, what it looks for, where, and what it leaves out.
        var terms: [String] = []
        if let sort = sortTerm(list.sort) { terms.append(sort) }
        let scoped = repository.map { narrowed(search.query, to: $0) } ?? search.query
        terms += scoped.split(separator: " ").map(String.init)
        // The app hides drafts from a list that does not want them, and
        // it hides them after the fetch. GitHub has to be told, or the
        // browser shows rows the app does not.
        if list.content == .pullRequests, !list.includeDrafts {
            terms.append("-is:draft")
        }

        guard !terms.isEmpty else { return nil }
        let query = terms.map(encoded).joined(separator: "+")
        return URL(string: "\(page(of: list.content))/search?q=\(query)")
    }

    /// How the list is sorted, where GitHub can be told.
    ///
    /// Two of the four cannot: ordering by type, and by how long a
    /// review has been waited for, are this app's own arithmetic over
    /// what came back. Saying nothing leaves GitHub's own default, which
    /// is better than naming a sort that means something else.
    private static func sortTerm(_ sort: ListSort) -> String? {
        switch sort {
        case .updated: "sort:updated-desc"
        case .created: "sort:created-desc"
        case .type, .waiting: nil
        }
    }

    /// Everything but the unreserved characters, with the spaces as `+`.
    ///
    /// Which is how GitHub writes these links itself, and `:` and `@`
    /// have to be escaped for the query to survive the trip.
    private static func encoded(_ term: String) -> String {
        term.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? term
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func page(of content: ListContent) -> String {
        switch content {
        case .pullRequests: "https://github.com/pulls"
        case .issues: "https://github.com/issues"
        }
    }

    /// How many searches the list stands on, so a button can say that it
    /// is opening one of several rather than all of them.
    public static func searchCount(
        for list: SavedList, repositoryFilters: [String]
    ) -> Int {
        ListQuery.searches(for: list, repositoryFilters: repositoryFilters).count
    }
}
