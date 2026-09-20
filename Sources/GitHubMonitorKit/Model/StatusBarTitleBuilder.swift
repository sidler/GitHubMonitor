import Foundation

/// How the two counts are rendered in the menu bar.
public enum StatusBarStyle: String, CaseIterable, Codable, Sendable {
    /// `⑂ 3  ◉ 5` -- both counts, each with its own symbol.
    case separate
    /// A single number: everything that wants attention.
    case sum
    /// Like `separate`, but a count of zero collapses to just its symbol.
    case hideZero

    public var label: String {
        switch self {
        case .separate: "Both counts"
        case .sum: "Single total"
        case .hideZero: "Both, hide zeros"
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
    public static let warningSymbol = "exclamationmark.triangle.fill"
    public static let unconfiguredSymbol = "key.slash"

    public static func segments(
        pullRequests: Int,
        mentions: Int,
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

        switch style {
        case .sum:
            return [.symbol(pullRequestSymbol), .text(" \(pullRequests + mentions)")]

        case .separate:
            return [
                .symbol(pullRequestSymbol), .text(" \(pullRequests)  "),
                .symbol(mentionSymbol), .text(" \(mentions)"),
            ]

        case .hideZero:
            var segments: [StatusBarSegment] = [.symbol(pullRequestSymbol)]
            if pullRequests > 0 {
                segments.append(.text(" \(pullRequests)"))
            }
            segments.append(.text("  "))
            segments.append(.symbol(mentionSymbol))
            if mentions > 0 {
                segments.append(.text(" \(mentions)"))
            }
            return segments
        }
    }

    /// Plain-text rendering used for accessibility labels and tests.
    public static func accessibilityLabel(pullRequests: Int, mentions: Int, health: StatusBarHealth) -> String {
        switch health {
        case .unconfigured: "GitHub Monitor: no token configured"
        case .failing: "GitHub Monitor: last refresh failed"
        case .ok: "GitHub Monitor: \(pullRequests) reviews requested, \(mentions) unread mentions"
        }
    }
}
