import Foundation
import Testing

@testable import GitHubMonitorKit

/// A pull request's detail, its files, its commits and its conversations
/// are fetched once and then claimed. Somebody pushing has to be what
/// lets go of them, or the diff goes on showing the code of the commit it
/// was read at while the commit list beside it names the new one.
@MainActor
@Suite("A pull request that has moved on")
struct MovedOnTests {
    private func item(_ id: String, head: String?) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "Thing", repository: "octo/server",
            author: "mira", authorAvatarURL: nil,
            url: URL(string: "https://github.com/octo/server/pull/1")!,
            isDraft: false, updatedAt: .now, reviewDecision: .reviewRequired,
            checks: .none, headCommit: head
        )
    }

    @Test("A head that has changed is named")
    func changed() {
        let moved = AppState.movedOn(
            [item("a", head: "bbb"), item("b", head: "ccc")],
            fetchedAt: ["a": "aaa", "b": "ccc"]
        )
        #expect(moved == ["a"])
    }

    /// Nothing was fetched for it, so there is nothing to let go of.
    @Test("A pull request nobody has opened is left alone")
    func neverFetched() {
        #expect(AppState.movedOn([item("a", head: "bbb")], fetchedAt: [:]).isEmpty)
    }

    /// GitHub not naming a commit is not the same as it having changed,
    /// and throwing the cache away on that would be throwing it away on
    /// every refresh.
    @Test("A row without a head commit says nothing either way")
    func noHead() {
        #expect(
            AppState.movedOn([item("a", head: nil)], fetchedAt: ["a": "aaa"]).isEmpty
        )
    }
}

/// What the refresh does with them.
@MainActor
@Suite("Letting go of what moved on")
struct ForgetMovedOnTests {
    private func state(head: String) -> AppState {
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        let item = PullRequestItem(
            id: "pr-1", number: 1, title: "Thing", repository: "octo/server",
            author: "mira", authorAvatarURL: nil,
            url: URL(string: "https://github.com/octo/server/pull/1")!,
            isDraft: false, updatedAt: .now, reviewDecision: .reviewRequired,
            checks: .none, headCommit: head
        )
        state.listPullRequests["list"] = [item]
        state.detailCommits["pr-1"] = "aaa"
        state.pullRequestDetails["pr-1"] = .failed("x")
        state.changedFiles["pr-1"] = .loaded([])
        state.viewedFiles["pr-1"] = ["a.php": .viewed]
        state.reviewThreads["pr-1"] = []
        state.pullRequestCommits["pr-1"] = .loaded([])
        return state
    }

    private func controller(_ state: AppState) -> RefreshController {
        RefreshController(
            state: state,
            trendStore: TrendStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
            )
        )
    }

    /// All four go together, so they cannot afterwards come from
    /// different commits.
    @Test("Everything cached for it goes, and the record with it")
    func forgets() {
        let state = self.state(head: "bbb")
        controller(state).forgetWhatMovedOn()

        #expect(state.detailCommits["pr-1"] == nil)
        #expect(state.pullRequestDetails["pr-1"] == nil)
        #expect(state.changedFiles["pr-1"] == nil)
        #expect(state.viewedFiles["pr-1"] == nil)
        #expect(state.reviewThreads["pr-1"] == nil)
        #expect(state.pullRequestCommits["pr-1"] == nil)
    }

    @Test("A pull request still at the commit it was read at is untouched")
    func keeps() {
        let state = self.state(head: "aaa")
        controller(state).forgetWhatMovedOn()

        #expect(state.detailCommits["pr-1"] == "aaa")
        #expect(state.changedFiles["pr-1"] != nil)
        #expect(state.pullRequestCommits["pr-1"] != nil)
    }

    /// Remarks written and not sent are the one thing here nobody else
    /// has a copy of. A push must not take them.
    @Test("An unsent draft survives the pull request moving on")
    func keepsTheDraft() {
        let state = self.state(head: "bbb")
        state.reviewDrafts["pr-1"] = ReviewDraft(pullRequestID: "pr-1", commit: "aaa")
        controller(state).forgetWhatMovedOn()
        #expect(state.reviewDrafts["pr-1"] != nil)
    }
}
