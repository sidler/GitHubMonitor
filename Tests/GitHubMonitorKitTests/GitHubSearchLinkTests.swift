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
        return try #require(components.queryItems?.first { $0.name == "q" }?.value)
    }

    @Test("The address carries the query and the kind of thing it finds")
    func address() throws {
        let url = try #require(
            GitHubSearchLink.address(
                for: list("is:pr is:open review-requested:@me"), repositoryFilters: []
            )
        )
        #expect(url.absoluteString.hasPrefix("https://github.com/search?"))
        let written = try query(of: url)
        #expect(written == "is:pr is:open review-requested:@me")
        #expect(url.absoluteString.contains("type=pullrequests"))
    }

    @Test("An issue list lands in the issues tab")
    func issues() throws {
        let url = try #require(
            GitHubSearchLink.address(
                for: list("is:issue is:open", content: .issues), repositoryFilters: []
            )
        )
        #expect(url.absoluteString.contains("type=issues"))
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
        #expect(written == "is:pr is:open")
    }

    @Test("A list with nothing in it has no address")
    func empty() {
        #expect(GitHubSearchLink.address(for: list(""), repositoryFilters: []) == nil)
    }
}
