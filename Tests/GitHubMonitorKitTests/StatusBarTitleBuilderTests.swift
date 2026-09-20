import Testing
@testable import GitHubMonitorKit

@Suite("Status bar title")
struct StatusBarTitleBuilderTests {
    @Test("Separate style shows both counts with their own symbols")
    func separateStyle() {
        let segments = StatusBarTitleBuilder.segments(
            pullRequests: 3, mentions: 5, style: .separate, health: .ok
        )
        #expect(segments == [
            .symbol(StatusBarTitleBuilder.pullRequestSymbol), .text(" 3  "),
            .symbol(StatusBarTitleBuilder.mentionSymbol), .text(" 5"),
        ])
    }

    @Test("Sum style collapses both counts into one number")
    func sumStyle() {
        let segments = StatusBarTitleBuilder.segments(
            pullRequests: 3, mentions: 5, style: .sum, health: .ok
        )
        #expect(segments == [.symbol(StatusBarTitleBuilder.pullRequestSymbol), .text(" 8")])
    }

    @Test("hideZero drops the number but keeps the symbol")
    func hideZeroStyle() {
        let segments = StatusBarTitleBuilder.segments(
            pullRequests: 0, mentions: 2, style: .hideZero, health: .ok
        )
        #expect(segments == [
            .symbol(StatusBarTitleBuilder.pullRequestSymbol), .text("  "),
            .symbol(StatusBarTitleBuilder.mentionSymbol), .text(" 2"),
        ])
    }

    /// A failed refresh must never render as a plain "0" -- that would be
    /// indistinguishable from an empty review queue.
    @Test("Unhealthy states replace the counts entirely", arguments: [
        (StatusBarHealth.failing, StatusBarTitleBuilder.warningSymbol),
        (StatusBarHealth.unconfigured, StatusBarTitleBuilder.unconfiguredSymbol),
    ])
    func unhealthyStatesHideCounts(health: StatusBarHealth, expectedSymbol: String) {
        for style in StatusBarStyle.allCases {
            let segments = StatusBarTitleBuilder.segments(
                pullRequests: 7, mentions: 9, style: style, health: health
            )
            #expect(segments == [.symbol(expectedSymbol)])
        }
    }

    @Test("Accessibility label names both counts")
    func accessibilityLabel() {
        let label = StatusBarTitleBuilder.accessibilityLabel(
            pullRequests: 2, mentions: 4, health: .ok
        )
        #expect(label.contains("2 reviews requested"))
        #expect(label.contains("4 unread mentions"))
    }
}
