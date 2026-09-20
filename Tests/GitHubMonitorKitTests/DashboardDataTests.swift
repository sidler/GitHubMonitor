import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Dashboard data")
struct DashboardDataTests {
    private func item(author: String, draft: Bool = false, id: String = UUID().uuidString) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "octo/platform", author: author,
            authorAvatarURL: URL(string: "https://example.com/\(author).png"),
            url: URL(string: "https://github.com")!, isDraft: draft,
            updatedAt: .now, reviewDecision: .none, checks: .none
        )
    }

    @Test("Pull requests are counted per author")
    func perAuthor() throws {
        let data = DashboardData.summarise(
            [item(author: "a"), item(author: "a"), item(author: "b")],
            repository: "octo/platform"
        )
        #expect(data.authors.count == 2)
        #expect(data.authors.first { $0.author == "a" }?.ready == 2)
        #expect(data.authors.first { $0.author == "b" }?.ready == 1)
    }

    /// Drafts are not waiting on anyone; folding them into the same number
    /// would overstate how much review work an author has queued up.
    @Test("Drafts are counted apart from ready pull requests")
    func draftsSeparate() throws {
        let data = DashboardData.summarise(
            [item(author: "a"), item(author: "a", draft: true), item(author: "a", draft: true)],
            repository: "r"
        )
        let author = try #require(data.authors.first)
        #expect(author.ready == 1)
        #expect(author.drafts == 2)
        #expect(author.total == 3)
    }

    @Test("Totals add up across authors")
    func totals() {
        let data = DashboardData.summarise(
            [item(author: "a"), item(author: "b", draft: true), item(author: "c")],
            repository: "r"
        )
        #expect(data.totalReady == 2)
        #expect(data.totalDrafts == 1)
        #expect(data.total == 3)
    }

    /// The chart answers "who is waiting on a review", so an author with six
    /// drafts must not outrank one with two ready pull requests.
    @Test("Authors are ordered by work that is actually waiting")
    func orderedByReady() {
        let data = DashboardData.summarise(
            [item(author: "drafter", draft: true), item(author: "drafter", draft: true),
             item(author: "drafter", draft: true), item(author: "reviewer"),
             item(author: "reviewer")],
            repository: "r"
        )
        #expect(data.authors.map(\.author) == ["reviewer", "drafter"])
    }

    @Test("Equal counts fall back to name order so rows do not shuffle")
    func stableOrder() {
        let data = DashboardData.summarise(
            [item(author: "zoe"), item(author: "adam")],
            repository: "r"
        )
        #expect(data.authors.map(\.author) == ["adam", "zoe"])
    }

    @Test("An author with only drafts still appears")
    func draftsOnlyAuthor() throws {
        let data = DashboardData.summarise([item(author: "a", draft: true)], repository: "r")
        let author = try #require(data.authors.first)
        #expect(author.ready == 0)
        #expect(author.drafts == 1)
    }

    @Test("No pull requests yields no authors")
    func empty() {
        let data = DashboardData.summarise([PullRequestItem](), repository: "r")
        #expect(data.authors.isEmpty)
        #expect(data.total == 0)
    }

    @Test("The repository query is scoped to one repository")
    func repositoryQuery() {
        let query = PullRequestQuery.repositoryQuery("octo/platform")
        #expect(query.contains("repo:octo/platform"))
        #expect(query.contains("is:open"))
        // Drafts belong in the chart, so they must not be filtered out here.
        #expect(!query.contains("draft"))
        #expect(!query.contains("review-requested"))
    }
}

@Suite("Dashboard reviewer load")
struct DashboardReviewerTests {
    private func item(draft: Bool = false, id: String = UUID().uuidString) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "r", author: "someone",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: draft,
            updatedAt: .now, reviewDecision: .none, checks: .none
        )
    }

    private func reviewer(
        _ name: String,
        state: ReviewState,
        isTeam: Bool = false
    ) -> ReviewerStatus {
        ReviewerStatus(name: name, avatarURL: nil, state: state, isTeam: isTeam)
    }

    @Test("Outstanding reviews are counted per reviewer")
    func outstanding() throws {
        let data = DashboardData.summarise(
            [
                (item(), [reviewer("a", state: .pending), reviewer("b", state: .pending)]),
                (item(), [reviewer("a", state: .pending)]),
            ],
            repository: "r"
        )
        #expect(data.reviewers.first { $0.reviewer == "a" }?.pending == 2)
        #expect(data.reviewers.first { $0.reviewer == "b" }?.pending == 1)
        #expect(data.totalOutstandingReviews == 3)
    }

    /// A review already given is not outstanding; counting it would make an
    /// attentive reviewer look like the bottleneck.
    @Test("Reviews already given do not count as outstanding")
    func answeredReviewsExcluded() {
        let data = DashboardData.summarise(
            [(item(), [reviewer("a", state: .approved), reviewer("b", state: .changesRequested)])],
            repository: "r"
        )
        #expect(data.reviewers.isEmpty)
        #expect(data.totalOutstandingReviews == 0)
    }

    @Test("A reviewer with both answered and pending reviews keeps both counts")
    func mixedCounts() throws {
        let data = DashboardData.summarise(
            [
                (item(), [reviewer("a", state: .pending)]),
                (item(), [reviewer("a", state: .approved)]),
            ],
            repository: "r"
        )
        let load = try #require(data.reviewers.first)
        #expect(load.pending == 1)
        #expect(load.done == 1)
    }

    /// Nobody is blocked by a review request on a draft, so it belongs in its
    /// own segment rather than inflating the queue.
    @Test("Reviews owed on drafts are counted apart")
    func draftsApart() throws {
        let data = DashboardData.summarise(
            [
                (item(), [reviewer("a", state: .pending)]),
                (item(draft: true), [reviewer("a", state: .pending)]),
            ],
            repository: "r"
        )
        let load = try #require(data.reviewers.first)
        #expect(load.pending == 1)
        #expect(load.onDrafts == 1)
        #expect(load.outstanding == 2)
    }

    @Test("Teams appear as reviewers in their own right")
    func teams() throws {
        let data = DashboardData.summarise(
            [(item(), [reviewer("backend", state: .pending, isTeam: true)])],
            repository: "r"
        )
        let load = try #require(data.reviewers.first)
        #expect(load.reviewer == "backend")
        #expect(load.isTeam)
    }

    /// A user and a team can share a name; merging them would misreport both.
    @Test("A team and a user with the same name stay separate")
    func nameCollision() {
        let data = DashboardData.summarise(
            [(item(), [
                reviewer("core", state: .pending),
                reviewer("core", state: .pending, isTeam: true),
            ])],
            repository: "r"
        )
        #expect(data.reviewers.count == 2)
    }

    @Test("Reviewers are ordered by what is actually blocking")
    func ordering() {
        let data = DashboardData.summarise(
            [
                (item(draft: true), [reviewer("drafts-only", state: .pending)]),
                (item(draft: true), [reviewer("drafts-only", state: .pending)]),
                (item(draft: true), [reviewer("drafts-only", state: .pending)]),
                (item(), [reviewer("blocking", state: .pending)]),
            ],
            repository: "r"
        )
        #expect(data.reviewers.map(\.reviewer) == ["blocking", "drafts-only"])
    }

    @Test("Author counts are unaffected by the reviewer pass")
    func authorsStillCounted() {
        let data = DashboardData.summarise(
            [(item(), [reviewer("a", state: .pending)]), (item(draft: true), [])],
            repository: "r"
        )
        #expect(data.totalReady == 1)
        #expect(data.totalDrafts == 1)
    }
}
