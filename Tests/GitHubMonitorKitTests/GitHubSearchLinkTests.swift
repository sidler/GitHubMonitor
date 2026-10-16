import Foundation
import Testing

@testable import GitHubMonitorKit

@Suite("The same list, in the browser")
struct GitHubSearchLinkTests {
    private func list(
        _ query: String, content: ListContent = .pullRequests
    ) -> SavedList {
        SavedList(id: "l", title: "L", query: query, content: content)
    }

    private func query(of url: URL?) throws -> String {
        let url = try #require(url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let raw = try #require(components.queryItems?.first { $0.name == "q" }?.value)
        // Spaces travel as `+`; everything else URLComponents has
        // already turned back into itself.
        return raw.replacingOccurrences(of: "+", with: " ")
    }

    /// Not the generic `/search?type=` page: these are the pages GitHub
    /// links to itself, and they are what the queries this app writes
    /// are answered by.
    @Test("Pull requests go to the pulls page, issues to the issues page")
    func pages() throws {
        let pulls = try #require(
            GitHubSearchLink.address(
                for: list("is:pr is:open review-requested:@me"), repositoryFilters: []
            )
        )
        #expect(pulls.absoluteString.hasPrefix("https://github.com/pulls/search?q="))
        let written = try query(of: pulls)
        #expect(written == "sort:updated-desc is:pr is:open review-requested:@me -is:draft")

        let issues = try #require(
            GitHubSearchLink.address(
                for: list("is:issue is:open", content: .issues), repositoryFilters: []
            )
        )
        #expect(issues.absoluteString.hasPrefix("https://github.com/issues/search?q="))
    }

    /// The link somebody wrote out by hand as the one they wanted, kept
    /// here whole: the encoding is part of it -- `+` between the terms,
    /// and `:`, `@` and `/` escaped.
    @Test("The whole address, character for character")
    func exactly() throws {
        let reviews = SavedList(
            id: "reviews", title: "Reviews Requested",
            query: "is:pr is:open archived:false review-requested:@me",
            content: .pullRequests, sort: .updated, includeDrafts: false
        )
        let url = GitHubSearchLink.address(
            for: reviews, repositoryFilters: ["artemeon/core-ng"]
        )
        #expect(
            try #require(url).absoluteString == "https://github.com/pulls/search?q="
                + "sort%3Aupdated-desc+is%3Apr+is%3Aopen+archived%3Afalse"
                + "+review-requested%3A%40me+repo%3Aartemeon%2Fcore-ng+-is%3Adraft"
        )
    }

    /// The app hides drafts from a list that does not want them, and it
    /// hides them after the fetch -- so the browser has to be told, or
    /// it shows rows the app does not.
    @Test("Drafts are excluded where the list excludes them, and not otherwise")
    func drafts() throws {
        let withDrafts = SavedList(
            id: "d", title: "D", query: "is:pr is:open",
            content: .pullRequests, includeDrafts: true
        )
        let written = try query(of: GitHubSearchLink.address(
            for: withDrafts, repositoryFilters: []
        ))
        #expect(!written.contains("-is:draft"))
    }

    /// Two of the four orderings are this app's own arithmetic over what
    /// came back. Naming a sort that means something else would be worse
    /// than leaving GitHub's default.
    @Test("A sort GitHub cannot be told is left unsaid")
    func sorts() throws {
        func sortOf(_ sort: ListSort) throws -> String {
            try query(of: GitHubSearchLink.address(
                for: SavedList(
                    id: "s", title: "S", query: "is:pr",
                    content: .pullRequests, sort: sort, includeDrafts: true
                ),
                repositoryFilters: []
            ))
        }
        #expect(try sortOf(.updated) == "sort:updated-desc is:pr")
        #expect(try sortOf(.created) == "sort:created-desc is:pr")
        #expect(try sortOf(.waiting) == "is:pr")
        #expect(try sortOf(.type) == "is:pr")
    }

    /// The link is built from the same searches the app sends, so what
    /// the browser shows is what the list holds -- the global filter
    /// included.
    @Test("The repository filter is in the link, because it is in the list")
    func carriesTheFilter() throws {
        let url = GitHubSearchLink.address(
            for: list("is:pr is:open"), repositoryFilters: ["octo/server"]
        )
        let written = try query(of: url)
        #expect(written.contains("repo:octo/server"))
    }

    /// The one that is easy to get wrong: GitHub reads repeated `repo:`
    /// as "either of these", so adding one to a query that already names
    /// repositories widens the search at the moment somebody asked to
    /// narrow it.
    @Test("Narrowing to a repository replaces the ones already named")
    func narrowingReplaces() {
        let narrowed = GitHubSearchLink.narrowed(
            "is:pr is:open repo:octo/server repo:octo/toolkit", to: "octo/platform"
        )
        #expect(narrowed == "is:pr is:open repo:octo/platform")
    }

    @Test("An organisation is replaced too, for the same reason")
    func narrowingReplacesOrgs() {
        #expect(
            GitHubSearchLink.narrowed("is:pr org:octo", to: "octo/server")
                == "is:pr repo:octo/server"
        )
    }

    @Test("A quoted value survives being taken apart and put back")
    func quoted() {
        #expect(
            GitHubSearchLink.narrowed("is:issue label:\"needs decision\" org:octo", to: "o/r")
                == "is:issue label:\"needs decision\" repo:o/r"
        )
    }

    @Test("Standing on a repository, the link opens that repository's share")
    func narrowedAddress() throws {
        let url = GitHubSearchLink.address(
            for: list("is:pr is:open"),
            repositoryFilters: ["octo/server", "octo/toolkit"],
            narrowedTo: "octo/toolkit"
        )
        let q = try query(of: url)
        #expect(q.contains("repo:octo/toolkit"))
        #expect(!q.contains("repo:octo/server"))
    }

    /// GitHub's search cannot express the union of two queries, so a
    /// list standing on several opens as the first -- and the button has
    /// to be able to say so.
    @Test("A list of several searches opens the first, and says how many there are")
    func several() throws {
        let many = list("is:pr is:open\nis:pr is:merged")
        #expect(GitHubSearchLink.searchCount(for: many, repositoryFilters: []) == 2)
        let written = try query(of: GitHubSearchLink.address(for: many, repositoryFilters: []))
        #expect(written.contains("is:open"))
        #expect(!written.contains("is:merged"))
    }

    @Test("A list with nothing in it has no address")
    func empty() {
        #expect(GitHubSearchLink.address(for: list(""), repositoryFilters: []) == nil)
    }
}
