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
