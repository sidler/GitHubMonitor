import Foundation
import Testing
@testable import GitHubMonitorKit

@Suite("What is left of GitHub's hourly allowance")
struct RateBudgetTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func budget(_ remaining: Int, resetsIn seconds: TimeInterval = 600) -> RateBudget {
        RateBudget(
            remaining: remaining, limit: 5000,
            resetAt: now.addingTimeInterval(seconds), readAt: now
        )
    }

    @Test("Low enough to say something, low enough to stop")
    func floors() {
        #expect(!budget(4000).isLow)
        #expect(budget(499).isLow)
        #expect(!budget(499).isExhausted)
        #expect(budget(99).isExhausted)
        #expect(budget(99).isLow)
    }

    /// Once the hour has turned, what we measured describes an allowance
    /// that no longer exists.
    @Test("A reading from before the reset is worth nothing")
    func staleness() {
        let spent = budget(10, resetsIn: 600)
        #expect(!spent.isStale(asOf: now))
        #expect(spent.isStale(asOf: now.addingTimeInterval(700)))
    }

    /// GraphQL sometimes answers without one; then an hour is the longest a
    /// reading can mean anything, since that is the window itself.
    @Test("Without a reset time a reading expires after an hour")
    func noResetTime() {
        let unknown = RateBudget(remaining: 10, limit: 5000, resetAt: nil, readAt: now)
        #expect(!unknown.isStale(asOf: now.addingTimeInterval(3000)))
        #expect(unknown.isStale(asOf: now.addingTimeInterval(3700)))
    }

    @Test("The allowance with least left is the one worth warning about")
    func pressing() {
        let budgets = RateBudgets(graphQL: budget(450), rest: budget(120))
        #expect(budgets.pressing(asOf: now)?.remaining == 120)
    }

    @Test("Nothing is said while both allowances are comfortable")
    func quiet() {
        #expect(RateBudgets(graphQL: budget(4800), rest: budget(4900)).pressing(asOf: now) == nil)
        #expect(RateBudgets().pressing(asOf: now) == nil)
    }

    /// The notifications run out on their own schedule; that is no reason to
    /// stop refreshing the lists, which spend the other allowance.
    @Test("Only the query allowance pauses the lists")
    func pausing() {
        #expect(RateBudgets(graphQL: budget(50)).shouldPause(asOf: now))
        #expect(!RateBudgets(graphQL: budget(600)).shouldPause(asOf: now))
        #expect(!RateBudgets(rest: budget(5)).shouldPause(asOf: now))
        // Restored in the meantime, so there is nothing to wait for.
        #expect(!RateBudgets(graphQL: budget(50)).shouldPause(asOf: now.addingTimeInterval(700)))
        #expect(!RateBudgets().shouldPause(asOf: now))
    }

    @Test("The GraphQL answer is read across")
    func graphQLReading() throws {
        let payload: [String: Any] = [
            "rateLimit": ["limit": 5000, "remaining": 4321, "resetAt": "2026-09-25T13:15:15Z"],
        ]
        let budget = try #require(ListParser.budget(from: payload))
        #expect(budget.remaining == 4321)
        #expect(budget.limit == 5000)
        #expect(budget.resetAt == GitHubDate.date(from: "2026-09-25T13:15:15Z"))
    }

    @Test("An answer without the field says nothing rather than zero")
    func missingReading() {
        #expect(ListParser.budget(from: [:]) == nil)
        #expect(ListParser.budget(from: ["rateLimit": ["remaining": 10]]) == nil)
    }

    // MARK: - What it costs

    /// What one refresh was charged, carried over an hour.
    @Test("An hour is the last refresh, as often as it runs")
    func cost() {
        #expect(RefreshCost.pointsPerHour(refreshCost: 13, interval: 300) == 156)
        #expect(RefreshCost.pointsPerHour(refreshCost: 1, interval: 3600) == 1)
        #expect(RefreshCost.pointsPerHour(refreshCost: 0, interval: 300) == 0)
        #expect(RefreshCost.pointsPerHour(refreshCost: 13, interval: 0) == 0)
    }

    @Test("The sentence says what was charged, not what was guessed")
    func sentence() {
        let text = RefreshCost.sentence(lastRefreshCost: 13, interval: 300)
        #expect(text.contains("13 points"))
        #expect(text.contains("5 minutes"))
        #expect(text.contains("156"))

        #expect(RefreshCost.sentence(lastRefreshCost: 1, interval: 600).contains("1 point"))
        // Zero means GitHub did not say, not that the lists are idle.
        #expect(
            RefreshCost.sentence(lastRefreshCost: 0, interval: 300)
                .contains("did not say")
        )
    }

    /// Before the first refresh there is nothing to report, and a guess in
    /// its place is what this replaced.
    @Test("Nothing measured yet is said, not estimated")
    func unmeasured() {
        #expect(
            RefreshCost.sentence(lastRefreshCost: nil, interval: 300)
                .contains("nothing measured")
        )
    }

    /// GitHub charges each request of a paged fetch separately, and the
    /// sentence is about the refresh, not one request of it.
    @Test("A reading can stand for the whole run that produced it")
    func summed() {
        let reading = RateBudget(remaining: 4900, limit: 5000, resetAt: nil, cost: 4)
        #expect(reading.costing(13).cost == 13)
        #expect(reading.costing(13).remaining == 4900)
    }

    @Test("The cost GitHub charged is read across")
    func chargedCost() throws {
        let payload: [String: Any] = [
            "rateLimit": ["limit": 5000, "remaining": 4900, "cost": 7],
        ]
        let budget = try #require(ListParser.budget(from: payload))
        #expect(budget.cost == 7)
        // Charged or not, it has to be asked for to arrive.
        let document = ListQuery.document([
            ListSearch(listID: "l", content: .pullRequests, query: "is:pr"),
        ])
        #expect(document.contains("rateLimit { limit remaining resetAt cost }"))
    }
}
