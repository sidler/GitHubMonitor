import Testing
@testable import GitHubMonitorKit

@Suite("Status bar title")
struct StatusBarTitleBuilderTests {
    private func count(_ symbol: String, _ value: Int, title: String = "List") -> SurfaceCount {
        SurfaceCount(id: title, title: title, symbolName: symbol, count: value)
    }

    private var all: [SurfaceCount] {
        [
            count(StatusBarTitleBuilder.pullRequestSymbol, 3, title: "Reviews requested"),
            count(StatusBarTitleBuilder.mentionSymbol, 5, title: "Mentions"),
            count(StatusBarTitleBuilder.issueSymbol, 2, title: "Issues assigned"),
        ]
    }

    @Test("Separate style shows every count with its own symbol")
    func separateStyle() {
        let segments = StatusBarTitleBuilder.segments(counts: all, style: .separate, health: .ok)
        #expect(segments == [
            .symbol(StatusBarTitleBuilder.pullRequestSymbol), .text(" 3  "),
            .symbol(StatusBarTitleBuilder.mentionSymbol), .text(" 5  "),
            .symbol(StatusBarTitleBuilder.issueSymbol), .text(" 2"),
        ])
    }

    @Test("Sum style collapses every count into one number")
    func sumStyle() {
        let segments = StatusBarTitleBuilder.segments(counts: all, style: .sum, health: .ok)
        #expect(segments == [.symbol(StatusBarTitleBuilder.pullRequestSymbol), .text(" 10")])
    }

    @Test("hideZero drops the number but keeps the symbol")
    func hideZeroStyle() {
        let segments = StatusBarTitleBuilder.segments(
            counts: [
                count(StatusBarTitleBuilder.pullRequestSymbol, 0),
                count(StatusBarTitleBuilder.mentionSymbol, 2),
            ],
            style: .hideZero,
            health: .ok
        )
        #expect(segments == [
            .symbol(StatusBarTitleBuilder.pullRequestSymbol), .text("  "),
            .symbol(StatusBarTitleBuilder.mentionSymbol), .text(" 2"),
        ])
    }

    /// However many lists there are, each is rendered: a count that appears
    /// in one style and not another is a count the user can lose.
    @Test("Every count is rendered whatever the style")
    func everyCountInEveryStyle() {
        for style in StatusBarStyle.allCases {
            let without = StatusBarTitleBuilder.segments(
                counts: Array(all.prefix(2)), style: style, health: .ok
            )
            let with = StatusBarTitleBuilder.segments(counts: all, style: style, health: .ok)
            #expect(without != with)
        }
    }

    /// A list switched off for the menu bar leaves no trace there -- neither
    /// its symbol, nor its number in the total.
    @Test("Only the lists switched on are rendered")
    func hiddenListsAreAbsent() {
        let segments = StatusBarTitleBuilder.segments(
            counts: [count(StatusBarTitleBuilder.issueSymbol, 4)], style: .separate, health: .ok
        )
        #expect(segments == [.symbol(StatusBarTitleBuilder.issueSymbol), .text(" 4")])
    }

    /// Switching everything off is a way of asking for a quiet menu bar, so
    /// the icon still has to be there to click.
    @Test("With nothing switched on the icon stays, without a number")
    func everythingHidden() {
        let segments = StatusBarTitleBuilder.segments(counts: [], style: .separate, health: .ok)
        #expect(segments == [.symbol(StatusBarTitleBuilder.quietSymbol)])
        #expect(
            StatusBarTitleBuilder.accessibilityLabel(counts: [], health: .ok)
                .contains("no counts shown")
        )
    }

    /// A refresh that failed with nothing behind it must never render as a
    /// plain "0" -- that would be indistinguishable from an empty review
    /// queue, which is the opposite of what it means.
    @Test("States with nothing to show replace the counts entirely", arguments: [
        (StatusBarHealth.failing, StatusBarTitleBuilder.warningSymbol),
        (StatusBarHealth.unconfigured, StatusBarTitleBuilder.unconfiguredSymbol),
    ])
    func unhealthyStatesHideCounts(health: StatusBarHealth, expectedSymbol: String) {
        for style in StatusBarStyle.allCases {
            let segments = StatusBarTitleBuilder.segments(counts: all, style: style, health: health)
            #expect(segments == [.symbol(expectedSymbol)])
        }
    }

    /// The point of the state: a timeout is usually over before anybody
    /// looks, and trading five counts for a warning triangle throws away
    /// what the menu bar is for to report something that has passed.
    @Test("A failure with earlier counts behind it still shows them")
    func staleKeepsTheCounts() {
        for style in StatusBarStyle.allCases {
            #expect(
                StatusBarTitleBuilder.segments(counts: all, style: style, health: .stale)
                    == StatusBarTitleBuilder.segments(counts: all, style: style, health: .ok)
            )
        }
        // Specifically not the thing it used to show.
        #expect(
            !StatusBarTitleBuilder.segments(counts: all, style: .separate, health: .stale)
                .contains(.symbol(StatusBarTitleBuilder.warningSymbol))
        )
    }

    /// Not hidden, only moved somewhere that costs nothing until asked.
    @Test("Stale counts say so in the tooltip")
    func staleTooltip() {
        let label = StatusBarTitleBuilder.accessibilityLabel(counts: all, health: .stale)
        #expect(label.contains("3 reviews requested"))
        #expect(label.contains("last refresh failed"))
        #expect(!StatusBarTitleBuilder.accessibilityLabel(counts: all, health: .ok)
            .contains("last refresh failed"))
    }

    @Test("Both failures count as a failure for the panes that go red")
    func isFailure() {
        #expect(StatusBarHealth.stale.isFailure)
        #expect(StatusBarHealth.failing.isFailure)
        #expect(!StatusBarHealth.ok.isFailure)
        // No token is not a failed refresh; it is a question nobody asked.
        #expect(!StatusBarHealth.unconfigured.isFailure)
    }

    /// The lists are named by the user, so the spoken label names them too.
    @Test("Accessibility label names every list on show")
    func accessibilityLabel() {
        let label = StatusBarTitleBuilder.accessibilityLabel(counts: all, health: .ok)
        #expect(label.contains("3 reviews requested"))
        #expect(label.contains("5 mentions"))
        #expect(label.contains("2 issues assigned"))
    }
}

@MainActor
@Suite("What a failed refresh does to the menu bar")
struct RefreshFailureHealthTests {
    private func state() -> AppState {
        let state = AppState(settings: Settings(store: TestDefaults.make()))
        state.hasToken = true
        return state
    }

    /// The case this exists for: the counts were right a minute ago, a
    /// request timed out, and they are still the best answer available.
    @Test("A failure after a good refresh keeps the counts")
    func failureAfterSuccess() {
        let state = state()
        state.loadState = .loaded(.now)
        state.loadState = .failed("The request timed out.")
        #expect(state.health == .stale)
    }

    /// Nothing has ever arrived, so there are no counts -- only zeros,
    /// which would read as an empty queue rather than an unanswered one.
    @Test("A failure before any good refresh does not")
    func failureFromCold() {
        let state = state()
        state.loadState = .failed("The request timed out.")
        #expect(state.health == .failing)
    }

    /// Once the app has seen one good answer it is never cold again, so a
    /// later failure is stale rather than empty however many times it
    /// happens.
    @Test("A second failure is still stale")
    func repeatedFailures() {
        let state = state()
        state.loadState = .loaded(.now)
        for _ in 0..<3 { state.loadState = .failed("Timed out.") }
        #expect(state.health == .stale)
        state.loadState = .loaded(.now)
        #expect(state.health == .ok)
    }

    /// A missing token is a different thing from a failed request, and the
    /// key symbol says so.
    @Test("No token outranks a failure")
    func withoutToken() {
        let state = state()
        state.loadState = .loaded(.now)
        state.hasToken = false
        state.loadState = .failed("Keychain unavailable")
        #expect(state.health == .unconfigured)
    }

    /// Paused is not failed: GitHub answered, and said to come back later.
    @Test("Pausing on the budget shows the counts as usual")
    func paused() {
        let state = state()
        state.loadState = .loaded(.now)
        state.loadState = .paused(until: nil)
        #expect(state.health == .ok)
    }
}
