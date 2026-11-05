import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("Pull request legend")
struct PullRequestLegendTests {
    private func item(
        id: String = UUID().uuidString,
        decision: ReviewDecision = .reviewRequired,
        checks: ChecksStatus = .success,
        merge: MergeStatus = .unknown,
        reviews: ReviewTally = .none,
        draft: Bool = false
    ) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: draft,
            updatedAt: .now, reviewDecision: decision, checks: checks,
            mergeStatus: merge, reviews: reviews
        )
    }

    /// The merge symbol sits with the checks in a row, and does the same in
    /// the legend.
    @Test("A conflicting pull request is explained after its checks")
    func mergeEntry() {
        let symbols = PullRequestLegend.symbols(for: [
            item(decision: .approved, checks: .success, merge: .conflicting),
        ])
        #expect(symbols == [.review(.approved), .checks(.success), .merge(.conflicting)])
    }

    /// Nothing is drawn for a pull request GitHub has not judged yet, so
    /// nothing is explained for one either.
    @Test("An unknown merge state adds no entry")
    func unknownMerge() {
        let symbols = PullRequestLegend.symbols(for: [item(merge: .unknown)])
        #expect(!symbols.contains { if case .merge = $0 { true } else { false } })
    }

    /// The legend explains the list below it, so a state nothing on screen is
    /// in would spend the status bar's width on a symbol nobody can see.
    @Test("Only the symbols on screen are explained")
    func onlyWhatIsShown() {
        let symbols = PullRequestLegend.symbols(for: [
            item(decision: .approved, checks: .failure),
        ])
        #expect(symbols.contains(.review(.approved)))
        #expect(symbols.contains(.checks(.failure)))
        #expect(!symbols.contains(.review(.changesRequested)))
        #expect(!symbols.contains(.checks(.success)))
    }

    @Test("Each symbol is explained once, however many rows use it")
    func noRepeats() {
        let symbols = PullRequestLegend.symbols(for: [
            item(decision: .approved, checks: .success),
            item(decision: .approved, checks: .success),
        ])
        #expect(symbols.count == Set(symbols).count)
        #expect(symbols.count == 2)
    }

    /// Grouped the way a row reads: the pull request's own state first, then
    /// its checks, then the reviewer counts.
    @Test("Entries follow the order of the row")
    func order() {
        let symbols = PullRequestLegend.symbols(for: [
            item(
                decision: .changesRequested,
                checks: .pending,
                reviews: ReviewTally(accepted: 1, declined: 0, pending: 2),
                draft: true
            ),
        ])
        #expect(symbols == [
            .review(.changesRequested),
            .checks(.pending),
            .reviewers(.accepted),
            .reviewers(.pending),
            .draft,
        ])
    }

    @Test("A reviewer count of zero is not explained")
    func zeroTally() {
        let symbols = PullRequestLegend.symbols(for: [
            item(reviews: ReviewTally(accepted: 0, declined: 3, pending: 0)),
        ])
        #expect(symbols.contains(.reviewers(.declined)))
        #expect(!symbols.contains(.reviewers(.accepted)))
        #expect(!symbols.contains(.reviewers(.pending)))
    }

    @Test("The draft badge is explained only when a draft is shown")
    func drafts() {
        #expect(!PullRequestLegend.symbols(for: [item()]).contains(.draft))
        #expect(PullRequestLegend.symbols(for: [item(draft: true)]).contains(.draft))
    }

    /// An empty list has nothing to explain, and the status bar should not
    /// carry a legend for rows that are not there.
    @Test("An empty list has no legend")
    func empty() {
        #expect(PullRequestLegend.symbols(for: []).isEmpty)
    }

    /// Every entry has to say something; a symbol with no wording is not a
    /// legend entry.
    @Test("Every entry carries wording and a tooltip")
    func wording() {
        let all: [LegendSymbol] =
            ReviewDecision.allCases.map(LegendSymbol.review)
            + ChecksStatus.allCases.map(LegendSymbol.checks)
            + ReviewTallyKind.allCases.map(LegendSymbol.reviewers)
            + [.draft]

        for symbol in all {
            #expect(!symbol.label.isEmpty)
            #expect(!symbol.help.isEmpty)
        }
        // The draft badge is drawn as itself; everything else needs a symbol.
        #expect(all.filter { $0.symbolName == nil } == [.draft])
    }
}

/// Pressing a symbol in the legend narrows the list to the rows carrying
/// it. The question it answers is "which three have failing checks?".
@Suite("Narrowing a list by its legend")
struct LegendFilterTests {
    private func item(
        decision: ReviewDecision = .reviewRequired,
        checks: ChecksStatus = .success,
        merge: MergeStatus = .unknown,
        reviews: ReviewTally = .none,
        draft: Bool = false
    ) -> PullRequestItem {
        PullRequestItem(
            id: UUID().uuidString, number: 1, title: "t", repository: "octo/platform",
            author: "a", authorAvatarURL: nil, url: URL(string: "https://github.com")!,
            isDraft: draft, updatedAt: .now, reviewDecision: decision, checks: checks,
            mergeStatus: merge, reviews: reviews
        )
    }

    @Test("A symbol matches exactly the rows that draw it")
    func matching() {
        let failing = item(checks: .failure)
        let passing = item(checks: .success)

        #expect(LegendSymbol.checks(.failure).matches(failing))
        #expect(LegendSymbol.checks(.failure).matches(passing) == false)
        #expect(LegendSymbol.checks(.success).matches(passing))
    }

    @Test("The review decision, the merge state and the draft mark all narrow")
    func otherKinds() {
        #expect(LegendSymbol.review(.approved).matches(item(decision: .approved)))
        #expect(LegendSymbol.review(.approved).matches(item(decision: .changesRequested)) == false)
        #expect(LegendSymbol.merge(.conflicting).matches(item(merge: .conflicting)))
        #expect(LegendSymbol.merge(.conflicting).matches(item(merge: .mergeable)) == false)
        #expect(LegendSymbol.draft.matches(item(draft: true)))
        #expect(LegendSymbol.draft.matches(item(draft: false)) == false)
    }

    /// A reviewer count is a number on the row, so the symbol stands for
    /// the pull requests whose number is not zero.
    @Test("A reviewer count matches the ones that have any")
    func reviewers() {
        let waiting = item(reviews: ReviewTally(accepted: 0, declined: 0, pending: 2))
        let settled = item(reviews: ReviewTally(accepted: 1, declined: 0, pending: 0))

        #expect(LegendSymbol.reviewers(.pending).matches(waiting))
        #expect(LegendSymbol.reviewers(.pending).matches(settled) == false)
        #expect(LegendSymbol.reviewers(.accepted).matches(settled))
    }

    /// Neither is ever drawn on a pull request row, so neither can be
    /// pressed to narrow a list of them.
    @Test("The issue symbols narrow nothing in a list of pull requests")
    func issueSymbols() {
        #expect(LegendSymbol.comments.matches(item()) == false)
        #expect(LegendSymbol.milestone.matches(item()) == false)
    }
}

/// What the list draws while a legend symbol is pressed, and what the
/// legend itself is still built from.
@Suite("A list narrowed by its legend")
@MainActor
struct LegendFilterStateTests {
    private func item(_ id: String, checks: ChecksStatus) -> PullRequestItem {
        PullRequestItem(
            id: id, number: 1, title: "t", repository: "octo/platform", author: "a",
            authorAvatarURL: nil, url: URL(string: "https://github.com")!, isDraft: false,
            updatedAt: .now, reviewDecision: .reviewRequired, checks: checks,
            mergeStatus: .unknown, reviews: .none
        )
    }

    private func state() -> (AppState, SavedList) {
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        let list = SavedList(id: "a", title: "A", query: "is:pr", content: .pullRequests)
        state.listPullRequests[list.id] = [
            item("1", checks: .failure),
            item("2", checks: .success),
            item("3", checks: .failure),
        ]
        return (state, list)
    }

    @Test("Pressing a symbol leaves only the rows carrying it")
    func narrows() {
        let (app, list) = state()

        app.legendFilter = .checks(.failure)

        #expect(app.shownPullRequests(in: list).map(\.id).sorted() == ["1", "3"])
    }

    /// Built from the unnarrowed list, or pressing a symbol would leave a
    /// legend of one entry and no way back to the rest.
    @Test("The legend still describes the whole list")
    func legendIsUnnarrowed() {
        let (app, list) = state()
        app.legendFilter = .checks(.failure)

        let symbols = PullRequestLegend.symbols(for: app.selectedPullRequests(in: list))

        #expect(symbols.contains(.checks(.success)))
        #expect(symbols.contains(.checks(.failure)))
    }

    @Test("Pressing it again puts the rest back")
    func clears() {
        let (app, list) = state()
        app.legendFilter = .checks(.failure)

        app.legendFilter = nil

        #expect(app.shownPullRequests(in: list).count == 3)
    }

    /// A question asked of one list. Carried to the next one it would
    /// narrow a list nobody had asked it about -- and the symbol it
    /// stands for may not even be drawn there.
    @Test("Going to another list asks the question again")
    func clearedOnMoving() {
        let (app, list) = state()
        app.sidebarSelection = .list(id: list.id, repository: nil)
        app.legendFilter = .checks(.failure)

        app.sidebarSelection = .dashboard

        #expect(app.legendFilter == nil)
    }
}
