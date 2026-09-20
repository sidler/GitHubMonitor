import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Pull request query")
struct PullRequestQueryTests {
    @Test("Without teams there is a single personal search")
    func personalOnly() {
        let queries = PullRequestQuery.searchQueries(
            login: "sidler", teamSlugs: [], repositoryFilters: []
        )
        #expect(queries == ["is:pr is:open archived:false review-requested:sidler"])
    }

    /// Repeated review qualifiers are AND-ed by GitHub, so personal and team
    /// requests cannot share one query.
    @Test("Each team gets its own search")
    func teamsGetSeparateQueries() {
        let queries = PullRequestQuery.searchQueries(
            login: "sidler", teamSlugs: ["octo/backend", "octo/server"], repositoryFilters: []
        )
        #expect(queries.count == 3)
        #expect(queries[1].contains("team-review-requested:octo/backend"))
        #expect(queries[2].contains("team-review-requested:octo/server"))
        // No query may mix the two audiences.
        #expect(queries.allSatisfy { query in
            !(query.contains("review-requested:sidler") && query.contains("team-review-requested:"))
        })
    }

    @Test("Repository filters become repo: and org: qualifiers")
    func repositoryScope() {
        #expect(PullRequestQuery.repositoryScope(["octo"]) == " org:octo")
        #expect(PullRequestQuery.repositoryScope(["octo/server"]) == " repo:octo/server")
        #expect(PullRequestQuery.repositoryScope([]) == "")
        #expect(PullRequestQuery.repositoryScope(["  ", ""]) == "")
    }

    @Test("The repository scope applies to every audience")
    func scopeAppliesEverywhere() {
        let queries = PullRequestQuery.searchQueries(
            login: "sidler", teamSlugs: ["octo/backend"], repositoryFilters: ["octo"]
        )
        #expect(queries.allSatisfy { $0.contains("org:octo") })
    }

    @Test("Team slugs are normalised and malformed ones dropped")
    func teamNormalisation() {
        let slugs = PullRequestQuery.normalisedTeams([
            " @Octo/Backend ", "nosuchslug", "octo/", "/backend", "",
        ])
        #expect(slugs == ["octo/backend"])
    }

    @Test("Every search becomes its own alias in one document")
    func documentAliases() {
        let document = PullRequestQuery.document(reviewRequested: ["a", "b"], authored: ["c"])
        #expect(document.contains("r0: search("))
        #expect(document.contains("r1: search("))
        #expect(document.contains("a0: search("))
        #expect(document.contains("fragment Results on SearchResultItemConnection"))
    }

    @Test("Authored pull requests are searched by author")
    func authoredQuery() {
        let query = PullRequestQuery.authoredQuery(login: "sidler", repositoryFilters: [])
        #expect(query == "is:pr is:open archived:false author:sidler")
        #expect(!query.contains("review-requested"))
    }

    @Test("The repository scope applies to the authored search too")
    func authoredScope() {
        let query = PullRequestQuery.authoredQuery(login: "sidler", repositoryFilters: ["octo"])
        #expect(query.contains("org:octo"))
    }

    /// A quote or backslash in a filter would otherwise break out of the
    /// GraphQL string and make the whole document invalid.
    /// The rows count reviewers, so the document has to bring them back --
    /// and cheaply: these fields are paid for on every refresh of every list.
    @Test("The list document asks for the reviewer counts")
    func reviewFields() {
        let document = PullRequestQuery.document(reviewRequested: ["q"], authored: [])
        #expect(document.contains("latestOpinionatedReviews(first: 10)"))
        // A plain count, so outstanding requests cost no nodes at all.
        #expect(document.contains("reviewRequests { totalCount }"))
        // Names and avatars belong to the detail pane; the rows only count.
        #expect(!document.contains("requestedReviewer"))
    }

    @Test("Quotes in a query are escaped")
    func escaping() {
        let document = PullRequestQuery.document(reviewRequested: ["repo:a/b \"quoted\""], authored: [])
        #expect(document.contains("\\\"quoted\\\""))
        #expect(!document.contains("search(query: \"repo:a/b \"quoted\""))
    }
}
