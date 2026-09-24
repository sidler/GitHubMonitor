import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Pull request filter")
struct PullRequestFilterTests {
    private func item(_ repository: String, draft: Bool = false) -> PullRequestItem {
        PullRequestItem(
            id: repository + (draft ? "-d" : ""), number: 1, title: "t",
            repository: repository, author: "a", authorAvatarURL: nil,
            url: URL(string: "https://github.com")!, isDraft: draft,
            updatedAt: .now, reviewDecision: .reviewRequired, checks: .none
        )
    }

    private var sample: [PullRequestItem] {
        [
            item("octo/server"),
            item("octo/website", draft: true),
            item("sidler/dotfiles"),
            item("other/thing", draft: true),
        ]
    }

    @Test("No repository filter keeps everything")
    func emptyFilter() {
        let result = PullRequestFilter.matchingRepositories(sample, repositoryFilters: [])
        #expect(result.count == 4)
    }

    @Test("A bare owner matches all of its repositories")
    func ownerFilter() {
        let result = PullRequestFilter.matchingRepositories(sample, repositoryFilters: ["octo"])
        #expect(result.map(\.repository) == ["octo/server", "octo/website"])
    }

    @Test("A full name matches only that repository")
    func fullNameFilter() {
        let result = PullRequestFilter.matchingRepositories(sample, repositoryFilters: ["octo/server"])
        #expect(result.map(\.repository) == ["octo/server"])
    }

    /// "octo" must not pull in a different owner whose name merely starts
    /// with the same letters.
    @Test("Owner matching does not leak into similarly named owners")
    func ownerPrefixDoesNotLeak() {
        let items = [item("octo/server"), item("octonautics/server")]
        let result = PullRequestFilter.matchingRepositories(items, repositoryFilters: ["octo"])
        #expect(result.map(\.repository) == ["octo/server"])
    }

    @Test("Filters ignore case and surrounding whitespace")
    func normalisation() {
        let result = PullRequestFilter.matchingRepositories(sample, repositoryFilters: ["  OCTO/Server "])
        #expect(result.map(\.repository) == ["octo/server"])
    }

    @Test("Blank entries are not treated as a filter")
    func blankEntriesIgnored() {
        let result = PullRequestFilter.matchingRepositories(sample, repositoryFilters: ["", "   "])
        #expect(result.count == 4)
    }
}
