import Testing
@testable import GitHubMonitorKit

@Suite("Status bar title")
struct StatusBarTitleBuilderTests {
    /// The three counts as the app shows them by default.
    private let all: [(list: WatchedList, count: Int)] = [
        (.reviews, 3), (.mentions, 5), (.issues, 2),
    ]

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
            counts: [(.reviews, 0), (.mentions, 2)], style: .hideZero, health: .ok
        )
        #expect(segments == [
            .symbol(StatusBarTitleBuilder.pullRequestSymbol), .text("  "),
            .symbol(StatusBarTitleBuilder.mentionSymbol), .text(" 2"),
        ])
    }

    /// Every style has to be able to report the issues; a count that only
    /// appears in one of them is a count the user can lose by accident.
    @Test("Assigned issues are reported whatever the style")
    func issuesInEveryStyle() {
        for style in StatusBarStyle.allCases {
            let without = StatusBarTitleBuilder.segments(
                counts: [(.reviews, 1), (.mentions, 1)], style: style, health: .ok
            )
            let with = StatusBarTitleBuilder.segments(
                counts: [(.reviews, 1), (.mentions, 1), (.issues, 4)], style: style, health: .ok
            )
            #expect(without != with)
        }
    }

    /// A list switched off for the menu bar leaves no trace there -- neither
    /// its symbol, nor its number in the total.
    @Test("Only the lists switched on are rendered")
    func hiddenListsAreAbsent() {
        let segments = StatusBarTitleBuilder.segments(
            counts: [(.issues, 4)], style: .separate, health: .ok
        )
        #expect(segments == [.symbol(StatusBarTitleBuilder.issueSymbol), .text(" 4")])

        let total = StatusBarTitleBuilder.segments(
            counts: [(.reviews, 3)], style: .sum, health: .ok
        )
        #expect(total == [.symbol(StatusBarTitleBuilder.pullRequestSymbol), .text(" 3")])
    }

    /// Switching all three off is a way of asking for a quiet menu bar, so
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

    /// A failed refresh must never render as a plain "0" -- that would be
    /// indistinguishable from an empty review queue.
    @Test("Unhealthy states replace the counts entirely", arguments: [
        (StatusBarHealth.failing, StatusBarTitleBuilder.warningSymbol),
        (StatusBarHealth.unconfigured, StatusBarTitleBuilder.unconfiguredSymbol),
    ])
    func unhealthyStatesHideCounts(health: StatusBarHealth, expectedSymbol: String) {
        for style in StatusBarStyle.allCases {
            let segments = StatusBarTitleBuilder.segments(counts: all, style: style, health: health)
            #expect(segments == [.symbol(expectedSymbol)])
        }
    }

    @Test("Accessibility label names every count on show")
    func accessibilityLabel() {
        let label = StatusBarTitleBuilder.accessibilityLabel(
            counts: [(.reviews, 2), (.mentions, 4), (.issues, 6)], health: .ok
        )
        #expect(label.contains("2 reviews requested"))
        #expect(label.contains("4 unread mentions"))
        #expect(label.contains("6 issues assigned"))
    }
}
