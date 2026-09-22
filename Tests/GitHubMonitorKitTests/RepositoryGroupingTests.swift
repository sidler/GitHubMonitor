import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Repository grouping")
struct RepositoryGroupingTests {
    private struct Row: Identifiable {
        let id: String
        let repository: String
    }

    private func rows(_ pairs: [(String, String)]) -> [Row] {
        pairs.map { Row(id: $0.0, repository: $0.1) }
    }

    @Test("Items are bucketed by repository")
    func bucketing() {
        let groups = RepositoryGrouping.group(
            rows([("a", "o/one"), ("b", "o/two"), ("c", "o/one")]),
            by: \.repository
        )
        #expect(groups.count == 2)
        #expect(groups.first?.repository == "o/one")
        #expect(groups.first?.items.map(\.id) == ["a", "c"])
    }

    /// The repository demanding most attention belongs at the top.
    @Test("Bigger groups come first")
    func orderedBySize() {
        let groups = RepositoryGrouping.group(
            rows([("a", "o/small"), ("b", "o/big"), ("c", "o/big"), ("d", "o/big")]),
            by: \.repository
        )
        #expect(groups.map(\.repository) == ["o/big", "o/small"])
    }

    /// Equal sizes must not shuffle between refreshes.
    @Test("Equal sizes fall back to name order")
    func stableOrderOnTies() {
        let groups = RepositoryGrouping.group(
            rows([("a", "o/zeta"), ("b", "o/alpha")]),
            by: \.repository
        )
        #expect(groups.map(\.repository) == ["o/alpha", "o/zeta"])
    }

    @Test("Order within a group is preserved")
    func orderWithinGroup() {
        let groups = RepositoryGrouping.group(
            rows([("first", "o/one"), ("second", "o/one"), ("third", "o/one")]),
            by: \.repository
        )
        #expect(groups.first?.items.map(\.id) == ["first", "second", "third"])
    }

    @Test("No items means no groups")
    func empty() {
        #expect(RepositoryGrouping.group([Row](), by: \.repository).isEmpty)
    }

    @Test("Suggestions merge both lists and drop the unknown placeholder")
    func suggestions() {
        let pullRequest = PullRequestItem(
            id: "1", number: 1, title: "t", repository: "octo/server", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: .now, reviewDecision: .none, checks: .none
        )
        let notification = NotificationItem(
            id: "n", title: "t", repository: "sidler/dotfiles", avatarURL: nil,
            reason: .mention, updatedAt: .now, subjectType: "Issue",
            latestCommentAPIURL: nil, subjectAPIURL: nil
        )
        // A notification whose repository could not be read.
        let unknown = NotificationItem(
            id: "n2", title: "t", repository: "?", avatarURL: nil,
            reason: .mention, updatedAt: .now, subjectType: "Issue",
            latestCommentAPIURL: nil, subjectAPIURL: nil
        )

        let repositories = RepositoryGrouping.repositories(
            pullRequests: [pullRequest], notifications: [notification, unknown]
        )
        #expect(repositories == ["octo/server", "sidler/dotfiles"])
        #expect(RepositoryGrouping.owners(of: repositories) == ["octo", "sidler"])
    }

    @Test("Duplicate repositories are suggested once")
    func suggestionsDeduplicate() {
        let item = { (repository: String) in
            NotificationItem(
                id: repository, title: "t", repository: repository, avatarURL: nil,
                reason: .mention, updatedAt: .now, subjectType: "Issue",
                latestCommentAPIURL: nil, subjectAPIURL: nil
            )
        }
        let repositories = RepositoryGrouping.repositories(
            pullRequests: [], notifications: [item("a/b"), item("a/c")]
        )
        #expect(RepositoryGrouping.owners(of: repositories) == ["a"])
    }
}

@Suite("Filter suggestions")
struct RepositorySuggestionTests {
    /// The filter narrows every list, so a repository the user only has
    /// issues in has to be offerable as one -- otherwise it would have to be
    /// typed from memory.
    @Test("Every list contributes a repository to filter by")
    func issuesAreOffered() {
        let pullRequest = PullRequestItem(
            id: "1", number: 1, title: "t", repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: .now, reviewDecision: .none, checks: .none
        )
        let issue = IssueItem(
            id: "i1", number: 1, title: "t", repository: "octo/toolkit", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, updatedAt: .now
        )

        let repositories = RepositoryGrouping.repositories(
            pullRequests: [pullRequest],
            notifications: [],
            issues: [issue]
        )
        #expect(repositories == ["octo/toolkit", "octo/platform"])
        #expect(RepositoryGrouping.owners(of: repositories) == ["octo"])
    }
}
