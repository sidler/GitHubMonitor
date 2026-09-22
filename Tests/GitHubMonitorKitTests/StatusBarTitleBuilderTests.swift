import Testing
@testable import GitHubMonitorKit

@Suite("Status bar title")
struct StatusBarTitleBuilderTests {
    @Test("Separate style shows every count with its own symbol")
    func separateStyle() {
        let segments = StatusBarTitleBuilder.segments(
            pullRequests: 3, mentions: 5, issues: 2, style: .separate, health: .ok
        )
        #expect(segments == [
            .symbol(StatusBarTitleBuilder.pullRequestSymbol), .text(" 3  "),
            .symbol(StatusBarTitleBuilder.mentionSymbol), .text(" 5  "),
            .symbol(StatusBarTitleBuilder.issueSymbol), .text(" 2"),
        ])
    }

    @Test("Sum style collapses every count into one number")
    func sumStyle() {
        let segments = StatusBarTitleBuilder.segments(
            pullRequests: 3, mentions: 5, issues: 2, style: .sum, health: .ok
        )
        #expect(segments == [.symbol(StatusBarTitleBuilder.pullRequestSymbol), .text(" 10")])
    }

    @Test("hideZero drops the number but keeps the symbol")
    func hideZeroStyle() {
        let segments = StatusBarTitleBuilder.segments(
            pullRequests: 0, mentions: 2, issues: 0, style: .hideZero, health: .ok
        )
        #expect(segments == [
            .symbol(StatusBarTitleBuilder.pullRequestSymbol), .text("  "),
            .symbol(StatusBarTitleBuilder.mentionSymbol), .text(" 2"), .text("  "),
            .symbol(StatusBarTitleBuilder.issueSymbol),
        ])
    }

    /// Every style has to be able to report the issues; a count that only
    /// appears in one of them is a count the user can lose by accident.
    @Test("Assigned issues are reported whatever the style")
    func issuesInEveryStyle() {
        for style in StatusBarStyle.allCases {
            let without = StatusBarTitleBuilder.segments(
                pullRequests: 1, mentions: 1, issues: 0, style: style, health: .ok
            )
            let with = StatusBarTitleBuilder.segments(
                pullRequests: 1, mentions: 1, issues: 4, style: style, health: .ok
            )
            #expect(without != with)
        }
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
                pullRequests: 7, mentions: 9, issues: 3, style: style, health: health
            )
            #expect(segments == [.symbol(expectedSymbol)])
        }
    }

    @Test("Accessibility label names every count")
    func accessibilityLabel() {
        let label = StatusBarTitleBuilder.accessibilityLabel(
            pullRequests: 2, mentions: 4, issues: 6, health: .ok
        )
        #expect(label.contains("2 reviews requested"))
        #expect(label.contains("4 unread mentions"))
        #expect(label.contains("6 issues assigned"))
    }
}
