import Foundation
import Testing
@testable import GitHubMonitorKit

@MainActor
@Suite("What an item points at")
struct LinkedItemsTests {
    private let repository = "octo/platform"

    private let pullRequests = SavedList(
        id: "reviews", title: "Reviews", query: "is:pr review-requested:@me",
        content: .pullRequests
    )
    private let issues = SavedList(
        id: "mine", title: "Issues", query: "is:issue assignee:@me", content: .issues
    )

    private func item(
        number: Int = 482, links: [ItemLink] = [], linkedTotal: Int? = nil
    ) -> PullRequestItem {
        PullRequestItem(
            id: "pr-\(number)", number: number, title: "t", repository: repository,
            author: "a", authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            isDraft: false, updatedAt: .now, reviewDecision: .none, checks: .none,
            links: links, linkedTotal: linkedTotal
        )
    }

    private func issue(number: Int = 318, links: [ItemLink] = []) -> IssueItem {
        IssueItem(
            id: "i-\(number)", number: number, title: "t", repository: repository,
            author: "a", authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            updatedAt: .now, links: links
        )
    }

    private func link(_ number: Int, _ kind: ItemLink.Kind) -> ItemLink {
        ItemLink(reference: ItemReference(repository: repository, number: number), kind: kind)
    }

    private func state() -> AppState {
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        state.settings.savedLists = [pullRequests, issues]
        return state
    }

    private func detail(body: String) -> PullRequestDetail {
        PullRequestDetail(
            headBranch: "b", baseBranch: "main", additions: 0, deletions: 0,
            changedFiles: 0, comments: 0, body: body, checks: [], reviewers: []
        )
    }

    /// The row knows what GitHub linked; the description adds the rest, and
    /// only once the description is there.
    @Test("Mentions in the description join the row's own links")
    func bodyJoinsIn() {
        let state = state()
        let pullRequest = item(links: [link(318, .closes)])

        #expect(state.links(of: pullRequest).map(\.reference.number) == [318])

        state.pullRequestDetails[pullRequest.id] = .loaded(detail(body: "Also see #4712."))
        let joined = state.links(of: pullRequest)
        #expect(joined.map(\.reference.number) == [318, 4712])
        #expect(joined.map(\.kind) == [.closes, .mentions])
    }

    /// A description that names its own number is talking about itself, and
    /// a panel offering to show you what you are reading is not an offer.
    @Test("An item does not link to itself")
    func noSelfLink() {
        let state = state()
        let pullRequest = item(number: 482)
        state.pullRequestDetails[pullRequest.id] = .loaded(
            detail(body: "Supersedes #482 in spirit.")
        )
        #expect(state.links(of: pullRequest).isEmpty)
    }

    /// GitHub counted eight; the query asked for five.
    @Test("Links GitHub counted but did not send are reported as a number")
    func overflow() {
        let state = state()
        #expect(state.unshownLinks(of: item(links: [link(1, .closes)], linkedTotal: 8)) == 7)
        #expect(state.unshownLinks(of: item(links: [link(1, .closes)], linkedTotal: 1)) == 0)
    }

    /// Mentions are read here, not counted by GitHub, so they must not make
    /// the "and N more" number go negative or shrink.
    @Test("Mentions do not count against GitHub's total")
    func mentionsDoNotCount() {
        let state = state()
        let pullRequest = item(links: [link(1, .closes), link(2, .mentions)], linkedTotal: 1)
        #expect(state.unshownLinks(of: pullRequest) == 0)
    }

    /// A guess that turned out to be nothing should not reach a chip, a
    /// card, or the height the panel is given for one.
    @Test("A number known to be nothing is dropped everywhere")
    func missingIsDropped() {
        let state = state()
        let pullRequest = item(links: [link(318, .closes)])
        state.pullRequestDetails[pullRequest.id] = .loaded(detail(body: "See #4712 and #9999."))
        state.linkedSummaries["\(repository)#9999"] = .missing

        #expect(state.links(of: pullRequest).map(\.reference.number) == [318, 4712])
    }

    /// Reading the same description again on every pass a view makes over
    /// it was measurable work for an answer that had not changed.
    @Test("A description is read for numbers once")
    func bodyReadOnce() {
        let state = state()
        let pullRequest = item()
        state.pullRequestDetails[pullRequest.id] = .loaded(detail(body: "See #4712."))

        let first = state.links(of: pullRequest)
        _ = state.links(of: pullRequest)
        _ = state.links(of: pullRequest)
        #expect(first.map(\.reference.number) == [4712])
        #expect(state.bodyLinks.reads == 1)

        // A new description is read again rather than answered from the
        // one before it.
        state.pullRequestDetails[pullRequest.id] = .loaded(detail(body: "See #4713."))
        #expect(state.links(of: pullRequest).map(\.reference.number) == [4713])
        #expect(state.bodyLinks.reads == 2)
    }

    /// A draft is only a draft while it is open.
    @Test(
        "A summary built here reports merged and closed, not just open",
        arguments: [
            (PullRequestState.merged, false, LinkedSummary.State.merged),
            (.closed, false, .closed),
            (.open, true, .draft),
            (.open, false, .open),
        ]
    )
    func localState(state: PullRequestState, isDraft: Bool, expected: LinkedSummary.State) {
        let pullRequest = PullRequestItem(
            id: "x", number: 1, title: "t", repository: repository, author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            isDraft: isDraft, state: state, updatedAt: .now,
            reviewDecision: .none, checks: .none
        )
        #expect(LinkedSummary.local(pullRequest, detail: nil).state == expected)
    }

    // MARK: - Going there

    @Test("An item in a list can be shown, and the sidebar follows")
    func reveal() {
        let state = state()
        let target = issue(number: 318)
        state.listIssues[issues.id] = [target]

        #expect(state.canReveal(target.reference))
        #expect(state.reveal(target.reference))
        #expect(state.sidebarSelection.listID == issues.id)
        #expect(state.inspectedIssueID == target.id)
        #expect(state.inspectedPullRequestID == nil)
    }

    @Test("An item in no list cannot be shown")
    func revealMissing() {
        let state = state()
        #expect(state.canReveal(ItemReference(repository: repository, number: 9999)) == false)
        #expect(state.reveal(ItemReference(repository: repository, number: 9999)) == false)
    }

    /// Going somewhere else means leaving the diff: it covers the whole
    /// window, including the row just selected.
    @Test("Showing an item puts away the diff being read")
    func revealClosesTheDiff() {
        let state = state()
        let target = item(number: 482)
        state.listPullRequests[pullRequests.id] = [target]
        state.openedDiff = OpenedDiff(
            pullRequestID: "other", path: "a.php", files: [], url: URL(string: "https://x.dev")!
        )

        #expect(state.reveal(target.reference))
        #expect(state.openedDiff == nil)
        #expect(state.inspectedPullRequestID == target.id)
    }

    /// The selection carries a repository narrowing, and the item revealed
    /// may not be in that repository.
    @Test("Showing an item drops any repository narrowing")
    func revealWidens() {
        let state = state()
        let target = item(number: 482)
        state.listPullRequests[pullRequests.id] = [target]
        state.sidebarSelection = .list(id: pullRequests.id, repository: "octo/other")

        #expect(state.reveal(target.reference))
        #expect(state.sidebarSelection.repository == nil)
    }
}

/// The made-up content is what the app shows without a token and what the
/// screenshots in the README are taken from, so it is worth it holding
/// together.
@MainActor
@Suite("The sample content")
struct SampleDataTests {
    @Test("Every link a sample row carries points at a sample row or a seeded summary")
    func linksResolve() {
        let rows = SampleData.reviewsRequested() + SampleData.myPullRequests()
        let issues = Set(SampleData.issues().map(\.reference.id))
        let summaries = SampleData.linkedSummaries()

        for link in rows.flatMap(\.links) {
            #expect(
                issues.contains(link.reference.id) || summaries[link.reference.id] != nil,
                "\(link.reference.id) is linked to by a sample row but is nowhere to be found"
            )
        }
    }

    /// The issue and the pull request that answer each other should agree
    /// about which one that is.
    @Test("The links between the sample rows point both ways")
    func linksAreMutual() {
        let rows = SampleData.reviewsRequested() + SampleData.myPullRequests()
        let issues = SampleData.issues()

        for issue in issues {
            for link in issue.links {
                guard let pullRequest = rows.first(where: { $0.reference == link.reference })
                else { continue }
                #expect(
                    pullRequest.links.contains { $0.reference == issue.reference },
                    "\(pullRequest.reference.id) does not link back to \(issue.reference.id)"
                )
            }
        }
    }

    /// The description is the one the Markdown rendering is exercised
    /// against, so the things it is meant to exercise have to be in it.
    @Test("The sample description carries a table, a checklist and numbers")
    func descriptionIsWorthRendering() {
        let blocks = MarkdownDocument.blocks(from: SampleData.description)
        #expect(blocks.contains { if case .table = $0 { true } else { false } })
        #expect(blocks.contains { block in
            guard case .bullets(let items) = block else { return false }
            return items.contains { $0.mark != .bullet }
        })
        #expect(!ItemReferences.inBody(
            SampleData.description, repository: SampleData.Repository.server
        ).isEmpty)
    }

    /// Nothing in here should name a real repository or a real person.
    @Test("The sample content is fiction")
    func isFiction() {
        let text = (SampleData.reviewsRequested() + SampleData.myPullRequests())
            .map { "\($0.repository) \($0.author) \($0.title)" }
            .joined(separator: " ")
            + SampleData.issues().map { "\($0.repository) \($0.author)" }.joined()
            + SampleData.description
        #expect(text.contains("octo/"))
    }
}
