import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Approving a pull request")
struct ApprovalTests {
    private let read = "22da5a177503201b9cbbe78802da6353299f74df"
    private let pushed = "b2c9ba6ffbb89df6662ae75e3dc6c4499ba3d9ff"

    private func head(_ commit: String, merged: Bool = false, closed: Bool = false) -> ApprovalQuery.HeadState {
        ApprovalQuery.HeadState(commit: commit, isMerged: merged, isClosed: closed)
    }

    @Test("The same commit is no reason to stop")
    func unchanged() {
        #expect(ApprovalQuery.refusal(comparing: head(read), against: read) == nil)
    }

    /// The whole point of the check: the diff on screen can be five minutes
    /// old, and five minutes is enough for someone to push.
    @Test("A commit pushed since the diff was read stops it")
    func moved() {
        let refusal = ApprovalQuery.refusal(comparing: head(pushed), against: read)
        #expect(refusal == .moved(from: read, to: pushed))
        // The message names both, shortened the way a commit is written.
        let message = try? #require(refusal?.localizedDescription)
        #expect(message?.contains("22da5a1") == true)
        #expect(message?.contains("b2c9ba6") == true)
        #expect(message?.contains("Nothing was approved") == true)
    }

    @Test("A pull request that is gone stops it too")
    func goneAway() {
        #expect(ApprovalQuery.refusal(comparing: head(read, merged: true), against: read) == .merged)
        #expect(ApprovalQuery.refusal(comparing: head(read, closed: true), against: read) == .closed)
        // Merged wins over closed: it is the more useful thing to be told.
        #expect(
            ApprovalQuery.refusal(comparing: head(read, merged: true, closed: true), against: read)
                == .merged
        )
    }

    /// A row fetched before the app asked for the head commit has nothing to
    /// compare against. Refusing then would block approving for a reason
    /// nobody can act on.
    @Test("Nothing to compare against is not a refusal")
    func noCommitKnown() {
        #expect(ApprovalQuery.refusal(comparing: head(read), against: nil) == nil)
    }

    @Test("The head is read across, with the two ways it can be gone")
    func headParsing() throws {
        let payload: [String: Any] = [
            "node": ["headRefOid": read, "merged": false, "closed": true],
        ]
        let state = try ApprovalQuery.head(from: payload)
        #expect(state.commit == read)
        #expect(state.isClosed)
        #expect(!state.isMerged)
    }

    @Test("A pull request that is not there is an error, not a silent pass")
    func headMissing() {
        #expect(throws: GitHubError.self) { try ApprovalQuery.head(from: [:]) }
    }

    /// The sentence people actually read before pressing. Where auto-merge
    /// is armed -- which at this account is nearly every pull request -- it
    /// has to say that this may ship the change, not just that a checkmark
    /// appears.
    @Test("The confirmation says what is at stake")
    func confirmation() {
        let plain = ApprovalQuery.confirmation(
            repository: "octo/platform", number: 35709, isAutoMergeArmed: false
        )
        #expect(plain.contains("octo/platform #35709"))
        #expect(plain.contains("cannot be taken back"))
        #expect(!plain.lowercased().contains("merge"))

        let armed = ApprovalQuery.confirmation(
            repository: "octo/platform", number: 35709, isAutoMergeArmed: true
        )
        #expect(armed.contains("cannot be taken back"))
        #expect(armed.contains("Auto-merge is armed"))
        #expect(armed.contains("it will be merged"))
    }

    /// The commit binding is the difference between approving what was read
    /// and approving whatever happens to be there when the request lands.
    @Test("The mutation is bound to a commit")
    func mutationShape() {
        #expect(ApprovalQuery.approveDocument.contains("commitOID: $commit"))
        #expect(ApprovalQuery.approveDocument.contains("event: APPROVE"))
        // Nothing else: no body, no comments, no threads.
        #expect(!ApprovalQuery.approveDocument.contains("body"))
    }
}

@Suite("What the row says after approving")
struct ApprovalTallyTests {
    private func item(
        decision: ReviewDecision = .reviewRequired,
        viewer: ViewerReview? = nil,
        reviews: ReviewTally = ReviewTally(accepted: 1, declined: 0, pending: 2)
    ) -> PullRequestItem {
        PullRequestItem(
            id: "1", number: 1, title: "t", repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: .now, reviewDecision: decision, checks: .none,
            viewerReview: viewer, reviews: reviews
        )
    }

    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("One more approval, one fewer awaited")
    func counted() {
        let after = item().countingViewerApproval(at: moment)
        #expect(after.reviews.accepted == 2)
        #expect(after.reviews.pending == 1)
        #expect(after.viewerReview?.state == .approved)
        #expect(after.viewerReview?.submittedAt == moment)
    }

    /// The pull request's own verdict is GitHub's to give: one approval does
    /// not settle it where two are required, and claiming otherwise would
    /// have the row say something nobody checked.
    @Test("The pull request's own decision is left alone")
    func decisionUntouched() {
        #expect(item().countingViewerApproval().reviewDecision == .reviewRequired)
    }

    /// Approving after asking for changes supersedes the earlier review, so
    /// both must not be left standing.
    @Test("An approval replaces this person's earlier objection")
    func supersedes() {
        let before = item(
            decision: .changesRequested,
            viewer: ViewerReview(state: .changesRequested, submittedAt: moment),
            reviews: ReviewTally(accepted: 0, declined: 1, pending: 0)
        )
        let after = before.countingViewerApproval()
        #expect(after.reviews.declined == 0)
        #expect(after.reviews.accepted == 1)
    }

    @Test("Approving twice does not count twice")
    func alreadyApproved() {
        let before = item(
            viewer: ViewerReview(state: .approved, submittedAt: moment),
            reviews: ReviewTally(accepted: 1, declined: 0, pending: 0)
        )
        #expect(before.countingViewerApproval().reviews.accepted == 1)
    }

    @Test("The counts never go below nothing")
    func noNegatives() {
        let before = item(reviews: ReviewTally(accepted: 0, declined: 0, pending: 0))
        let after = before.countingViewerApproval()
        #expect(after.reviews.pending == 0)
        #expect(after.reviews.declined == 0)
        #expect(after.reviews.accepted == 1)
    }
}

@Suite("What the pane says after approving")
struct ApprovalDetailTests {
    private func detail(reviewers: [ReviewerStatus]) -> PullRequestDetail {
        PullRequestDetail(
            headBranch: "fix/thing", baseBranch: "main",
            additions: 1, deletions: 1, changedFiles: 1, comments: 0,
            checks: [], reviewers: reviewers
        )
    }

    private func reviewer(
        _ name: String, _ state: ReviewState, isTeam: Bool = false
    ) -> ReviewerStatus {
        ReviewerStatus(name: name, avatarURL: nil, state: state, isTeam: isTeam)
    }

    /// The pane is open behind the diff that was just approved from, and a
    /// detail fetched in the moment after the mutation can still answer with
    /// the review set from before it.
    @Test("The approver appears without waiting for GitHub")
    func appears() {
        let after = detail(reviewers: [reviewer("chriskapp", .pending)])
            .countingApproval(by: "avery", avatarURL: nil)
        #expect(after.reviewers.map(\.name).contains("avery"))
        #expect(after.reviewers.first { $0.name == "avery" }?.state == .approved)
    }

    /// Their own earlier review is replaced, not joined: nobody stands in
    /// the list twice, least of all with two different opinions.
    @Test("An earlier review by the same person is replaced")
    func replacesOwn() {
        let after = detail(reviewers: [
            reviewer("avery", .changesRequested),
            reviewer("chriskapp", .pending),
        ]).countingApproval(by: "avery", avatarURL: nil)

        #expect(after.reviewers.filter { $0.name == "avery" }.count == 1)
        #expect(after.reviewers.first { $0.name == "avery" }?.state == .approved)
    }

    /// A team that was asked is not this person, even where the names match.
    @Test("A team of the same name is left alone")
    func teamsUntouched() {
        let after = detail(reviewers: [reviewer("avery", .pending, isTeam: true)])
            .countingApproval(by: "avery", avatarURL: nil)
        #expect(after.reviewers.count == 2)
        #expect(after.reviewers.contains { $0.isTeam && $0.state == .pending })
    }

    @Test("A login differing only in case is still the same person")
    func caseInsensitive() {
        let after = detail(reviewers: [reviewer("Avery", .commented)])
            .countingApproval(by: "avery", avatarURL: nil)
        #expect(after.reviewers.count == 1)
        #expect(after.reviewers.first?.state == .approved)
    }

    /// Assembled here and fetched from GitHub must come out in the same
    /// order, or the list visibly reshuffles when the fetch lands.
    @Test("What is blocking stays first, what is settled stays last")
    func ordering() {
        let after = detail(reviewers: [
            reviewer("anna", .approved),
            reviewer("bea", .changesRequested),
        ]).countingApproval(by: "avery", avatarURL: nil)
        #expect(after.reviewers.map(\.name) == ["bea", "anna", "avery"])
    }

    @Test("Nothing else about the pull request is touched")
    func onlyReviewers() {
        let before = detail(reviewers: [])
        let after = before.countingApproval(by: "avery", avatarURL: nil)
        #expect(after.headBranch == before.headBranch)
        #expect(after.additions == before.additions)
        #expect(after.changedFiles == before.changedFiles)
        #expect(after.mergeStatus == before.mergeStatus)
    }
}

@MainActor
@Suite("An approval outlives GitHub's silence")
struct ApprovalPersistenceTests {
    private let list = SavedList(
        id: "reviews", title: "Reviews", query: "is:pr review-requested:@me",
        content: .pullRequests
    )

    private func item(_ id: String, viewer: ViewerReview? = nil) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: .now, reviewDecision: .reviewRequired, checks: .none,
            viewerReview: viewer,
            reviews: ReviewTally(accepted: 0, declined: 0, pending: 1)
        )
    }

    private func state() -> AppState {
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        state.settings.savedLists = [list]
        return state
    }

    /// The row comes from a search, the most lagged index GitHub has. A
    /// refresh landing seconds after an approval brings back the row as it
    /// was before it, and without this the approval would appear and then
    /// vanish for minutes.
    @Test("A row that comes back without the approval gets it back")
    func reapplied() {
        let before = item("1")
        let after = before.countingViewerApproval()
        #expect(after.reviews.accepted == 1)
        #expect(after.viewerReview?.state == .approved)

        // What a refresh brings: the row as GitHub still sees it.
        #expect(before.viewerReview?.state != .approved)
    }

    /// Once GitHub reports the approval there is nothing left to cover.
    /// The count does not move a second time, whichever way it is reached:
    /// the caller skips such a row, and the row would refuse anyway.
    @Test("A row that already carries the approval is not counted twice")
    func settled() {
        let settled = item("1", viewer: ViewerReview(state: .approved, submittedAt: .now))
        #expect(settled.viewerReview?.state == .approved)
        #expect(settled.countingViewerApproval().reviews.accepted == settled.reviews.accepted)
    }

    /// Signing out must leave nothing of the account behind -- not the
    /// lists, and not the diff of a private repository left open over them.
    @Test("Signing out clears what the token fetched")
    func signOutClears() {
        let state = state()
        state.hasToken = true
        state.listPullRequests[list.id] = [item("1")]
        state.changedFiles["1"] = .loaded([])
        state.openedDiff = OpenedDiff(
            pullRequestID: "1", path: nil, files: [],
            url: URL(string: "https://github.com/octo/platform/pull/1")!
        )
        state.approval = .confirming(pullRequestID: "1")
        state.inspectedPullRequestID = "1"
        state.linkedSummaries["octo/platform#9"] = .missing

        // Its own directory, so the test writes nothing into the cache the
        // app uses.
        let controller = RefreshController(
            state: state,
            trendStore: TrendStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString))
        )
        controller.signOut()

        #expect(state.openedDiff == nil)
        #expect(state.changedFiles.isEmpty)
        #expect(state.listPullRequests.isEmpty)
        #expect(state.inspectedPullRequestID == nil)
        #expect(state.approval == .idle)
        // Titles of issues in private repositories, like everything else.
        #expect(state.linkedSummaries.isEmpty)
        #expect(!state.hasToken)
    }
}

@Suite("The state an approval passes through")
struct ApprovalStateTests {
    @Test("A message belongs to the pull request it failed on")
    func messageIsScoped() {
        let state = ApprovalState.failed(pullRequestID: "1", message: "Branch protection")
        #expect(state.message(for: "1") == "Branch protection")
        #expect(state.message(for: "2") == nil)
        #expect(ApprovalState.idle.message(for: "1") == nil)
    }

    @Test("Only the two steps that are in flight count as busy")
    func busy() {
        #expect(ApprovalState.checking(pullRequestID: "1").isBusy)
        #expect(ApprovalState.sending(pullRequestID: "1").isBusy)
        #expect(!ApprovalState.idle.isBusy)
        #expect(!ApprovalState.failed(pullRequestID: "1", message: "no").isBusy)
        // Waiting for an answer is not the app being busy; the button under
        // the dialog must not look disabled.
        #expect(!ApprovalState.confirming(pullRequestID: "1").isBusy)
    }

    /// The question belongs to one pull request. Two overlays cannot be open
    /// at once, but the state is shared and must not raise a dialog over the
    /// wrong one.
    @Test("The question is asked about one pull request only")
    func confirmingIsScoped() {
        let state = ApprovalState.confirming(pullRequestID: "1")
        #expect(state.isConfirming("1"))
        #expect(!state.isConfirming("2"))
        #expect(!ApprovalState.idle.isConfirming("1"))
        #expect(!ApprovalState.sending(pullRequestID: "1").isConfirming("1"))
    }
}
