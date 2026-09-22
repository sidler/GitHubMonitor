import Foundation

/// How the counts are rendered in the menu bar.
public enum StatusBarStyle: String, CaseIterable, Codable, Sendable {
    /// `⑂ 3  ◉ 5  ◍ 2` -- every count, each with its own symbol.
    case separate
    /// A single number: everything that wants attention.
    case sum
    /// Like `separate`, but a count of zero collapses to just its symbol.
    case hideZero

    public var label: String {
        switch self {
        case .separate: "All counts"
        case .sum: "Single total"
        case .hideZero: "All, hide zeros"
        }
    }
}

/// Overall health of the data behind the counts. Drives whether we show
/// numbers at all -- stale or missing data must not masquerade as a real zero.
public enum StatusBarHealth: Equatable, Sendable {
    case ok
    /// No token configured yet.
    case unconfigured
    /// Last refresh failed (network, auth, rate limit).
    case failing
}

/// A renderable piece of the menu bar title. Kept symbolic rather than
/// pre-rendered so the layout logic stays unit testable.
public enum StatusBarSegment: Equatable, Sendable {
    case symbol(String)
    case text(String)
}

public enum StatusBarTitleBuilder {
    public static let pullRequestSymbol = "arrow.triangle.pull"
    public static let mentionSymbol = "bell"
    public static let issueSymbol = "smallcircle.filled.circle"
    public static let warningSymbol = "exclamationmark.triangle.fill"
    public static let unconfiguredSymbol = "key.slash"

    public static func segments(
        pullRequests: Int,
        mentions: Int,
        issues: Int,
        style: StatusBarStyle,
        health: StatusBarHealth
    ) -> [StatusBarSegment] {
        switch health {
        case .unconfigured:
            return [.symbol(unconfiguredSymbol)]
        case .failing:
            return [.symbol(warningSymbol)]
        case .ok:
            break
        }

        // One entry per count. Issues come last rather than beside the
        // other pull request count: the two that were here first keep the
        // place people are used to reading them in.
        let counts = [
            (symbol: pullRequestSymbol, value: pullRequests),
            (symbol: mentionSymbol, value: mentions),
            (symbol: issueSymbol, value: issues),
        ]

        switch style {
        case .sum:
            let total = counts.reduce(0) { $0 + $1.value }
            return [.symbol(pullRequestSymbol), .text(" \(total)")]

        case .separate:
            return counts.enumerated().flatMap { index, count -> [StatusBarSegment] in
                // Two spaces between groups, none after the last.
                let gap = index == counts.count - 1 ? "" : "  "
                return [.symbol(count.symbol), .text(" \(count.value)\(gap)")]
            }

        case .hideZero:
            // A zero says nothing its symbol does not already say, and three
            // counts in a menu bar are worth keeping narrow.
            return counts.enumerated().flatMap { index, count -> [StatusBarSegment] in
                var segments: [StatusBarSegment] = [.symbol(count.symbol)]
                if count.value > 0 {
                    segments.append(.text(" \(count.value)"))
                }
                if index < counts.count - 1 {
                    segments.append(.text("  "))
                }
                return segments
            }
        }
    }

    /// Plain-text rendering used for accessibility labels and tests.
    public static func accessibilityLabel(
        pullRequests: Int,
        mentions: Int,
        issues: Int,
        health: StatusBarHealth
    ) -> String {
        switch health {
        case .unconfigured: "GitHub Monitor: no token configured"
        case .failing: "GitHub Monitor: last refresh failed"
        case .ok:
            """
            GitHub Monitor: \(pullRequests) reviews requested, \
            \(mentions) unread mentions, \(issues) issues assigned
            """
        }
    }
}
