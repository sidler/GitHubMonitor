import Foundation
import Testing

@testable import GitHubMonitorKit

@Suite("What has to be true before a merge is offered")
struct MergeBlockerTests {
    private func item(
        state: PullRequestState = .open,
        draft: Bool = false,
        merge: MergeStatus = .mergeable,
        checks: ChecksStatus = .success,
        decision: ReviewDecision = .approved
    ) -> PullRequestItem {
        PullRequestItem(
            id: "1", number: 1, title: "t", repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: draft,
            state: state, updatedAt: .now, reviewDecision: decision, checks: checks,
            mergeStatus: merge, reviews: ReviewTally(accepted: 1, declined: 0, pending: 0)
        )
    }

    @Test("Nothing in the way, nothing to say")
    func clear() {
        #expect(MergeQuery.blocker(for: item()) == nil)
    }

    /// The three that were chosen, each said in its own words: a button
    /// that offers something and then reports a refusal has wasted
    /// somebody's nerve.
    @Test("A conflict stops it")
    func conflict() {
        #expect(MergeQuery.blocker(for: item(merge: .conflicting)) != nil)
    }

    @Test("Checks that are not green stop it, running as well as failed")
    func checks() {
        #expect(MergeQuery.blocker(for: item(checks: .failure)) != nil)
        #expect(MergeQuery.blocker(for: item(checks: .pending)) != nil)
        // A repository with no checks at all has nothing to wait for.
        #expect(MergeQuery.blocker(for: item(checks: .none)) == nil)
    }

    @Test("No approval stops it")
    func unapproved() {
        #expect(MergeQuery.blocker(for: item(decision: .reviewRequired)) != nil)
        #expect(MergeQuery.blocker(for: item(decision: .changesRequested)) != nil)
    }

    @Test("A draft, or something already closed, is not a thing to merge")
    func notOpen() {
        #expect(MergeQuery.blocker(for: item(draft: true)) != nil)
        #expect(MergeQuery.blocker(for: item(state: .merged)) != nil)
        #expect(MergeQuery.blocker(for: item(state: .closed)) != nil)
    }
}

@Suite("Reading a pull request again, immediately before merging it")
struct MergeReadinessTests {
    private func payload(
        commit: String = "abc",
        merged: Bool = false,
        closed: Bool = false,
        mergeable: String = "MERGEABLE",
        allows: [String: Bool] = ["squashMergeAllowed": true]
    ) -> [String: Any] {
        [
            "node": [
                "headRefOid": commit,
                "merged": merged,
                "closed": closed,
                "mergeable": mergeable,
                "repository": allows,
            ]
        ]
    }

    @Test("The commit, the state, and what the repository allows")
    func parses() throws {
        let readiness = try MergeQuery.readiness(
            from: payload(allows: ["mergeCommitAllowed": true, "rebaseMergeAllowed": true])
        )
        #expect(readiness.commit == "abc")
        #expect(readiness.mergeStatus == .mergeable)
        #expect(readiness.methods == [.merge, .rebase])
    }

    @Test("A repository that allows nothing says so rather than defaulting")
    func allowsNothing() throws {
        let readiness = try MergeQuery.readiness(from: payload(allows: [:]))
        #expect(readiness.methods.isEmpty)
        #expect(MergeQuery.refusal(comparing: readiness, against: "abc") != nil)
    }

    /// The guard the approval has, for the same reason: what was read is
    /// what is acted on, and a push arriving between the question and the
    /// answer is exactly when this matters.
    @Test("A branch that moved since it was read is refused")
    func moved() throws {
        let readiness = try MergeQuery.readiness(from: payload(commit: "new"))
        #expect(MergeQuery.refusal(comparing: readiness, against: "old") != nil)
        #expect(MergeQuery.refusal(comparing: readiness, against: "new") == nil)
    }

    @Test("Already merged, or closed, or conflicting by now")
    func gone() throws {
        #expect(
            try MergeQuery.refusal(
                comparing: MergeQuery.readiness(from: payload(merged: true)), against: "abc"
            ) != nil
        )
        #expect(
            try MergeQuery.refusal(
                comparing: MergeQuery.readiness(from: payload(closed: true)), against: "abc"
            ) != nil
        )
        #expect(
            try MergeQuery.refusal(
                comparing: MergeQuery.readiness(from: payload(mergeable: "CONFLICTING")),
                against: "abc"
            ) != nil
        )
    }

    @Test("Nothing to compare against is not a reason to refuse")
    func noCommitKnown() throws {
        let readiness = try MergeQuery.readiness(from: payload())
        #expect(MergeQuery.refusal(comparing: readiness, against: nil) == nil)
    }

    @Test("Something that is not a pull request is an error, not an empty answer")
    func notFound() {
        #expect(throws: GitHubError.self) {
            try MergeQuery.readiness(from: ["node": NSNull()])
        }
    }

    /// Without this the merge happens whatever the branch has become
    /// since, which is the one thing a merge must not do.
    @Test("The commit that was read is sent with the merge")
    func boundToACommit() {
        #expect(MergeQuery.mergeDocument.contains("expectedHeadOid: $commit"))
        #expect(MergeQuery.mergeDocument.contains("mergePullRequest"))
    }
}

@Suite("Where a merge stands")
struct MergeStateTests {
    @Test("Busy only while something is in flight")
    func busy() {
        #expect(MergeState.checking(pullRequestID: "1").isBusy)
        #expect(MergeState.sending(pullRequestID: "1").isBusy)
        #expect(!MergeState.idle.isBusy)
        #expect(!MergeState.failed(pullRequestID: "1", message: "no").isBusy)
        // The question being up is not busy: it is waiting for a person.
        #expect(!MergeState.confirming(pullRequestID: "1", methods: [.squash], commit: "a").isBusy)
    }

    @Test("A question belongs to one pull request, and says so")
    func whose() {
        let asking = MergeState.confirming(pullRequestID: "1", methods: [.squash], commit: "a")
        #expect(asking.isConfirming("1"))
        #expect(!asking.isConfirming("2"))
        #expect(asking.methods(for: "1") == [.squash])
        #expect(asking.methods(for: "2").isEmpty)
    }

    @Test("So does a refusal")
    func failure() {
        let failed = MergeState.failed(pullRequestID: "1", message: "it conflicts")
        #expect(failed.message(for: "1") == "it conflicts")
        #expect(failed.message(for: "2") == nil)
    }
}
